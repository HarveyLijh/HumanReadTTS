import SwiftUI
import AppKit
import os

/// The Markdown reader. Parses markdown via Foundation's
/// `AttributedString(markdown:options:)` (no third-party dep), then
/// walks the runs to translate `inlinePresentationIntent` /
/// `presentationIntent` attributes into NSFont / NSColor visual
/// styling that TextKit can render. The resulting NSAttributedString
/// is fed to an `NSTextView` host so we keep TextKit's lazy layout
/// for arbitrary-size markdown bodies.
///
/// Sentence segmentation happens on the *rendered* plain text so
/// the offsets stored in each `Sentence` are valid indices into the
/// `NSTextStorage` we display — no markdown-syntax characters get
/// in the way of the highlight.
///
/// Renamed from MarkdownPlaceholderView in M2.7 to reflect that
/// this is now the real reader, not a placeholder.
struct MarkdownReaderView: View {
    let url: URL
    let player: SpeechPlayer

    @State private var attributed: NSAttributedString = .init()
    @State private var sentences: [Sentence] = []
    @State private var loadFailed = false

    private static let log = Logger(subsystem: "app.rhea.mac", category: "markdown")

    var body: some View {
        Group {
            if loadFailed {
                errorState
            } else {
                MarkdownTextView(attributed: attributed, activeSentence: activeSentence)
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
            let raw = try String(contentsOf: url, encoding: .utf8)
            Self.log.info("read \(raw.count) chars")

            let parseStart = ContinuousClock.now
            let rendered = MarkdownRenderer.render(raw)
            Self.log.info("rendered markdown in \(ContinuousClock.now - parseStart, privacy: .public)")

            attributed = rendered
            loadFailed = false

            let segmentStart = ContinuousClock.now
            let plain = rendered.string
            let block = DocumentBlock(text: plain, pageIndex: 0, offsetInPage: 0)
            let parsed = await SentenceSegmenter.segment([block])
            Self.log.info("segmented \(parsed.count) sentences in \(ContinuousClock.now - segmentStart, privacy: .public)")

            sentences = parsed
            player.load(parsed)

            Self.log.info("TOTAL md load \(ContinuousClock.now - started, privacy: .public)")
        } catch {
            Self.log.error("failed to read \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            attributed = NSAttributedString()
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

// MARK: - Markdown rendering

/// Parses GFM-flavored markdown into an `NSAttributedString` with
/// sensible visual defaults for a reading view: New York body,
/// SF Mono for code, larger weight-bold headings, italics for
/// emphasis. No third-party dependency — Foundation's built-in
/// markdown parser is enough for the reader and gives us a clean
/// AttributedString we can decorate.
enum MarkdownRenderer {
    static func render(_ markdown: String) -> NSAttributedString {
        let bodyFont = NSFont(name: "New York", size: 16) ?? NSFont.systemFont(ofSize: 16)
        let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        let attributedString: AttributedString
        do {
            attributedString = try AttributedString(
                markdown: markdown,
                options: .init(
                    interpretedSyntax: .full,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        } catch {
            return NSAttributedString(
                string: markdown,
                attributes: [.font: bodyFont, .foregroundColor: NSColor.labelColor]
            )
        }

        let mutable = NSMutableAttributedString(attributedString: NSAttributedString(attributedString))
        let full = NSRange(location: 0, length: mutable.length)

        // Apply baseline body styling everywhere first.
        mutable.addAttribute(.font, value: bodyFont, range: full)
        mutable.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)

        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = 1.25
        para.paragraphSpacing = 8
        mutable.addAttribute(.paragraphStyle, value: para, range: full)

        // Walk per-run, look for presentation intents Foundation
        // attached during parsing, translate to visual attributes.
        for run in attributedString.runs {
            let range = NSRange(run.range, in: attributedString)
            guard range.length > 0, NSMaxRange(range) <= mutable.length else { continue }

            if let inline = run.inlinePresentationIntent {
                if inline.contains(.code) {
                    mutable.addAttribute(.font, value: monoFont, range: range)
                    mutable.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
                }
                if inline.contains(.stronglyEmphasized) {
                    mutable.addAttribute(.font, value: bold(of: mutable, at: range, baseSize: 16), range: range)
                }
                if inline.contains(.emphasized) {
                    mutable.addAttribute(.font, value: italic(of: mutable, at: range, baseSize: 16), range: range)
                }
            }

            if let block = run.presentationIntent {
                for component in block.components {
                    switch component.kind {
                    case .header(let level):
                        let size: CGFloat
                        switch level {
                        case 1: size = 28
                        case 2: size = 22
                        case 3: size = 18
                        default: size = 16
                        }
                        let headingFont = NSFont(
                            descriptor: bodyFont.fontDescriptor.withSymbolicTraits(.bold),
                            size: size
                        ) ?? NSFont.boldSystemFont(ofSize: size)
                        mutable.addAttribute(.font, value: headingFont, range: range)
                    case .codeBlock:
                        mutable.addAttribute(.font, value: monoFont, range: range)
                        mutable.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
                    default:
                        break
                    }
                }
            }
        }

        return mutable
    }

    private static func bold(of storage: NSMutableAttributedString, at range: NSRange, baseSize: CGFloat) -> NSFont {
        let current = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
            ?? NSFont.systemFont(ofSize: baseSize)
        let descriptor = current.fontDescriptor.withSymbolicTraits(current.fontDescriptor.symbolicTraits.union(.bold))
        return NSFont(descriptor: descriptor, size: current.pointSize) ?? NSFont.boldSystemFont(ofSize: baseSize)
    }

    private static func italic(of storage: NSMutableAttributedString, at range: NSRange, baseSize: CGFloat) -> NSFont {
        let current = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
            ?? NSFont.systemFont(ofSize: baseSize)
        let descriptor = current.fontDescriptor.withSymbolicTraits(current.fontDescriptor.symbolicTraits.union(.italic))
        return NSFont(descriptor: descriptor, size: current.pointSize) ?? current
    }
}

// MARK: - NSTextView host

private struct MarkdownTextView: NSViewRepresentable {
    let attributed: NSAttributedString
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
        guard let tv = nsView.documentView as? NSTextView,
              let storage = tv.textStorage else { return }

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
