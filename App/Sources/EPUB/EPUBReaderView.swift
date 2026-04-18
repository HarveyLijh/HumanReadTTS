import SwiftUI
import AppKit
import os

/// Renders an EPUB's concatenated NSAttributedString content in
/// the same NSTextView host the Markdown reader uses (so the
/// sentence-level highlight pipeline works unchanged). Playback
/// reuses the shared SpeechPlayer via RootView.
struct EPUBReaderView: View {
    let url: URL
    let player: SpeechPlayer

    @State private var rendered: NSAttributedString = .init()
    @State private var sentences: [Sentence] = []
    @State private var loadFailed = false
    @State private var errorMessage: String = ""

    private static let log = Logger(subsystem: "app.rhea.mac", category: "epub")

    var body: some View {
        Group {
            if loadFailed {
                errorState
            } else if rendered.length == 0 {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.rheaAccent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EPUBTextView(
                    attributed: rendered,
                    activeSentence: activeSentence,
                    spokenSubRange: player.spokenSubRange,
                    onReadFromOffset: handleReadFromOffset
                )
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

    private func handleReadFromOffset(_ offset: Int) {
        guard let idx = ReaderHitTester.sentenceIndex(
            forOffset: offset, in: sentences
        ) else { return }
        player.playFromSentence(idx)
    }

    private func load() async {
        let started = ContinuousClock.now
        do {
            let attributed = try await EPUBLoader.load(url: url)
            rendered = attributed
            loadFailed = false

            let plain = attributed.string
            let block = DocumentBlock(text: plain, pageIndex: 0, offsetInPage: 0)
            let parsed = await SentenceSegmenter.segment([block])
            sentences = parsed
            player.load(parsed)

            Self.log.info("TOTAL epub load \(ContinuousClock.now - started, privacy: .public) — \(parsed.count) sentences")
        } catch let error as EPUBLoader.LoadError {
            errorMessage = error.errorDescription ?? "Couldn't read EPUB."
            loadFailed = true
            player.load([])
        } catch {
            errorMessage = error.localizedDescription
            loadFailed = true
            player.load([])
        }
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.rheaAccent)
            Text(errorMessage.isEmpty ? "Couldn't read the EPUB." : errorMessage)
                .font(RheaFont.serif(18))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Drop another file to try again.")
                .font(RheaFont.ui(13))
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EPUBTextView: NSViewRepresentable {
    let attributed: NSAttributedString
    let activeSentence: Sentence?
    let spokenSubRange: NSRange?
    let onReadFromOffset: (Int) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(Color.rheaSurface)

        let textView = ClickableReaderTextView()
        textView.onReadFromOffset = onReadFromOffset
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.backgroundColor = NSColor(Color.rheaSurface)
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 32, height: 24)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude
        )

        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? ClickableReaderTextView,
              let storage = tv.textStorage else { return }

        tv.onReadFromOffset = onReadFromOffset

        if storage.length != attributed.length || storage.string != attributed.string {
            storage.setAttributedString(attributed)
        }
        applyHighlight(to: tv, storage: storage)
    }

    private func applyHighlight(to textView: NSTextView, storage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.removeAttribute(.backgroundColor, range: fullRange)

        if let sentence = activeSentence {
            let sentenceRange = NSRange(
                location: sentence.offsetInBlock,
                length: sentence.lengthInBlock
            )
            if NSMaxRange(sentenceRange) <= storage.length {
                let soft = NSColor(Color.rheaAccent).withAlphaComponent(0.25)
                storage.addAttribute(.backgroundColor, value: soft, range: sentenceRange)

                if let sub = spokenSubRange {
                    let subOrigin = sentence.offsetInBlock + sub.location
                    let subRange = NSRange(location: subOrigin, length: sub.length)
                    if NSMaxRange(subRange) <= storage.length {
                        let bright = NSColor(Color.rheaAccent).withAlphaComponent(0.55)
                        storage.addAttribute(.backgroundColor, value: bright, range: subRange)
                    }
                }

                storage.endEditing()
                textView.scrollRangeToVisible(sentenceRange)
                return
            }
        }
        storage.endEditing()
    }
}
