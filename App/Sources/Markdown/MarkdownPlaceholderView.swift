import SwiftUI
import AppKit
import os

/// Markdown rendering proper lands in M2.7. For M1.x we present the
/// file's raw contents in a monospaced text view so a dropped `.md`
/// file shows *something* useful, segment the contents into
/// sentences and feed them to the shared `SpeechPlayer`, and
/// highlight the currently-spoken sentence directly in the
/// `NSTextStorage`.
///
/// Uses an `NSTextView` host rather than SwiftUI's `Text` because
/// SwiftUI `Text` lays out its full string at once to compute the
/// intrinsic size — a 30s stall on a few-KB markdown file was
/// reproducible. `NSTextView` + `NSScrollView` use TextKit's lazy
/// layout, the standard Mac solution for arbitrary-size text
/// bodies. The same `NSTextStorage` is what we attach the active
/// sentence's amber background highlight to, so the highlight
/// matches the PDF viewer's behaviour for free.
struct MarkdownPlaceholderView: View {
    let url: URL
    let player: SpeechPlayer

    @State private var contents: String = ""
    @State private var sentences: [Sentence] = []
    @State private var loadFailed = false

    private static let log = Logger(subsystem: "app.rhea.mac", category: "markdown")

    var body: some View {
        Group {
            if loadFailed {
                errorState
            } else {
                MarkdownTextView(text: contents, activeSentence: activeSentence)
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private var activeSentence: Sentence? {
        guard let index = player.state.sentenceIndex,
              index >= 0, index < sentences.count else { return nil }
        return sentences[index]
    }

    private func load() async {
        let started = ContinuousClock.now
        do {
            let readStart = ContinuousClock.now
            let raw = try String(contentsOf: url, encoding: .utf8)
            let readDuration = ContinuousClock.now - readStart
            Self.log.info("read \(raw.count) chars in \(readDuration, privacy: .public)")

            contents = raw
            loadFailed = false

            let segmentStart = ContinuousClock.now
            let block = DocumentBlock(text: raw, pageIndex: 0, offsetInPage: 0)
            let parsed = await SentenceSegmenter.segment([block])
            let segmentDuration = ContinuousClock.now - segmentStart
            Self.log.info("segmented \(parsed.count) sentences in \(segmentDuration, privacy: .public)")

            sentences = parsed

            let loadStart = ContinuousClock.now
            player.load(parsed)
            let loadDuration = ContinuousClock.now - loadStart
            Self.log.info("player.load in \(loadDuration, privacy: .public)")

            let total = ContinuousClock.now - started
            Self.log.info("TOTAL md load \(total, privacy: .public)")
        } catch {
            Self.log.error("failed to read \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            contents = ""
            sentences = []
            loadFailed = true
            player.load([])
        }
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.rheaAccent)
            Text("Couldn't read \(url.lastPathComponent).")
                .font(RheaFont.serif(18))
                .foregroundStyle(.primary)
            Text("Drop another file to try again.")
                .font(RheaFont.ui(13))
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}

/// Thin SwiftUI host over `NSScrollView` + `NSTextView`. TextKit's
/// lazy layout handles arbitrary-size markdown bodies; the
/// `NSTextStorage` is mutated in-place to highlight the active
/// sentence with an amber background and to scroll it into view.
private struct MarkdownTextView: NSViewRepresentable {
    let text: String
    let activeSentence: Sentence?

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(Color.rheaSurface)

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor(Color.rheaSurface)
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude
        )
        textView.string = text

        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView,
              let storage = tv.textStorage else { return }

        if tv.string != text {
            tv.string = text
        }

        applyHighlight(to: tv, storage: storage)
    }

    private func applyHighlight(to textView: NSTextView, storage: NSTextStorage) {
        // Clear any existing highlight before applying a new one.
        // Doing it on the storage directly avoids a layout
        // round-trip per attribute change.
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.removeAttribute(.backgroundColor, range: fullRange)

        if let sentence = activeSentence {
            let range = NSRange(
                location: sentence.offsetInBlock,
                length: sentence.lengthInBlock
            )
            if NSMaxRange(range) <= storage.length {
                let amber = NSColor(Color.rheaAccent).withAlphaComponent(0.4)
                storage.addAttribute(.backgroundColor, value: amber, range: range)
                storage.endEditing()
                textView.scrollRangeToVisible(range)
                return
            }
        }
        storage.endEditing()
    }
}
