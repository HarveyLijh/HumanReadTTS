import SwiftUI
import AppKit
import os

/// Markdown rendering proper lands in M2.7. For M1.x we present the
/// file's raw contents in a monospaced text view so a dropped `.md`
/// file shows *something* useful, and we segment the contents into
/// sentences and feed them to the shared `SpeechPlayer` so playback
/// works the same way it does for PDFs.
///
/// Uses an `NSTextView` host rather than SwiftUI's `Text` because
/// SwiftUI `Text` lays out its full string at once to compute the
/// intrinsic size — a 30s stall on a few-KB markdown file is
/// reproducible. `NSTextView` + `NSScrollView` use TextKit's lazy
/// layout, which is the standard Mac solution for arbitrary-size
/// text bodies (used by Notes, Mail, every Cocoa text editor).
///
/// Per-sentence highlighting on this view is not implemented; the
/// proper Markdown reader in M2.7 will support it.
struct MarkdownPlaceholderView: View {
    let url: URL
    let player: SpeechPlayer

    @State private var contents: String = ""
    @State private var loadFailed = false

    private static let log = Logger(subsystem: "app.rhea.mac", category: "markdown")

    var body: some View {
        Group {
            if loadFailed {
                errorState
            } else {
                MarkdownTextView(text: contents)
            }
        }
        .task(id: url) {
            await load()
        }
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
            let sentences = await SentenceSegmenter.segment([block])
            let segmentDuration = ContinuousClock.now - segmentStart
            Self.log.info("segmented \(sentences.count) sentences in \(segmentDuration, privacy: .public)")

            let loadStart = ContinuousClock.now
            player.load(sentences)
            let loadDuration = ContinuousClock.now - loadStart
            Self.log.info("player.load in \(loadDuration, privacy: .public)")

            let total = ContinuousClock.now - started
            Self.log.info("TOTAL md load \(total, privacy: .public)")
        } catch {
            Self.log.error("failed to read \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            contents = ""
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

/// Thin SwiftUI host over `NSScrollView` + `NSTextView` so we get
/// TextKit's lazy layout for free. Read-only, monospaced, selectable.
private struct MarkdownTextView: NSViewRepresentable {
    let text: String

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
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text {
            tv.string = text
            tv.scroll(NSPoint.zero)
        }
    }
}
