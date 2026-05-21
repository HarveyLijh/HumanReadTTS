import SwiftUI
import AppKit

/// An in-app scratchpad for quick "type and have it read" flows —
/// no need to open a Markdown file first. Lives as a separate
/// document state alongside the PDF / Markdown / EPUB viewers;
/// picking it from File → New drops the user into an editable
/// text area.
///
/// Segmentation runs lazily when the user presses the transport's
/// play button (via `ensureLoaded()` — pushed into the shared
/// `SpeechPlayer` the first time play fires and whenever the user
/// resumes after editing). The scratchpad has no standalone "Read"
/// button: the HUD's play button is the single source of truth for
/// starting playback, exactly like for PDFs and EPUBs.
@MainActor
struct ScratchpadView: View {
    let player: SpeechPlayer
    @Binding var text: String

    enum ViewMode: String, CaseIterable, Identifiable {
        case raw = "Raw"
        case preview = "Preview"
        var id: Self { self }
    }

    @State private var viewMode: ViewMode = .raw
    @Bindable private var readerSettings = ReaderSettings.shared

    /// A snapshot of `text` at the last successful segment. When the
    /// user edits after playback has started, this drifts away from
    /// `text` and the next play auto-resegments.
    @State private var lastSegmentedText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            Divider()
            content
        }
        .background(Color.readAloudTTSSurface)
        .task(id: text) {
            // Debounce segmentation: wait for 400ms of quiet typing,
            // then push the fresh sentence queue into the player so
            // the HUD's play button always reads what's on screen.
            // `.task(id:)` cancels on every keystroke, so the body
            // only runs on the last change of a typing burst.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            ensureLoaded()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 14))
                .foregroundStyle(Color.readAloudTTSAccent)
            Text("Scratchpad")
                .font(ReadAloudTTSFont.serif(16))
                .foregroundStyle(.primary)
            Text(characterSummary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Picker("", selection: $viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
            .help("Raw = editable Markdown source. Preview = rendered.")

            FontSizeControl()

            Button {
                saveAsMarkdown()
            } label: {
                Label("Save as…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Export the scratchpad to a .md file.")

            Button {
                Task { @MainActor in
                    // Force-segment the latest text into the shared
                    // player before posting — the typing-debounce in
                    // `.task(id: text)` may not have fired if the user
                    // typed and clicked Export within 400 ms.
                    await loadIntoPlayerSynchronously()
                    NotificationCenter.default.post(
                        name: AppScene.exportNotification, object: nil
                    )
                }
            } label: {
                Label("Export audio…", systemImage: "waveform.badge.plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Render this scratchpad to an audio file (queues a background job).")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var content: some View {
        switch viewMode {
        case .raw:
            ScratchpadEditor(text: $text, fontScale: readerSettings.fontScale)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(Color.readAloudTTSSurface)
        case .preview:
            ScratchpadPreview(
                markdown: text,
                activeSentence: activeSentence,
                spokenSubRange: player.spokenSubRange,
                fontScale: readerSettings.fontScale,
                onReadFromOffset: handleReadFromOffset
            )
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(Color.readAloudTTSSurface)
        }
    }

    /// Double-click / "Read from here" handler for the Preview
    /// view. Mirrors `MarkdownReaderView.handleReadFromOffset` so
    /// clicks in the scratchpad behave identically to clicks in a
    /// loaded `.md` file.
    ///
    /// If the typing-debounce in `.task(id: text)` hasn't fired yet
    /// (the user typed and clicked within 400 ms), the player's
    /// sentence queue can lag the rendered text. We synchronously
    /// re-segment in that case so the offset resolves against the
    /// text the user is actually looking at.
    private func handleReadFromOffset(_ offset: Int) {
        Task { @MainActor in
            if text != lastSegmentedText {
                await loadIntoPlayerSynchronously()
            }
            guard let idx = ReaderHitTester.sentenceIndex(
                forOffset: offset, in: player.sentences
            ) else { return }
            player.playFromSentence(idx)
        }
    }

    /// The sentence currently being spoken — looked up against the
    /// player's queue, which `ensureLoaded()` segmented from the
    /// rendered Markdown plain text. Offsets line up with what the
    /// Preview text view renders, so the same highlight code the
    /// MarkdownReaderView uses works unchanged here.
    private var activeSentence: Sentence? {
        guard let index = player.state.sentenceIndex,
              index >= 0, index < player.sentences.count else { return nil }
        return player.sentences[index]
    }

    private var characterSummary: String {
        let count = text.count
        if count == 0 { return "Empty — type or paste to begin." }
        if count == 1 { return "1 character" }
        return "\(count) characters"
    }

    /// If the text has changed since the last segment (or never
    /// segmented), rebuild the sentence queue on the shared player.
    /// Runs the text through `MarkdownRenderer` first so Markdown
    /// syntax (`##`, `**`, `[link](url)`, etc.) never reaches the
    /// synthesizer — the spoken output matches the rendered Preview,
    /// not the raw typing. No-op when nothing has changed.
    /// Awaitable variant for callers that need the player's sentence
    /// queue to reflect the current scratchpad text *now* — the
    /// Export button uses this so a queued job sees the latest text
    /// rather than the last debounced snapshot.
    private func loadIntoPlayerSynchronously() async {
        let snapshot = text
        guard !snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let rendered = MarkdownRenderer.render(snapshot)
        let block = DocumentBlock(
            text: rendered.string, pageIndex: 0, offsetInPage: 0
        )
        let parsed = await SentenceSegmenter.segment([block])
        lastSegmentedText = snapshot
        player.load(parsed)
    }

    private func ensureLoaded() {
        let snapshot = text
        guard snapshot != lastSegmentedText else { return }
        guard !snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        lastSegmentedText = snapshot
        Task { @MainActor in
            let rendered = MarkdownRenderer.render(snapshot)
            let block = DocumentBlock(
                text: rendered.string, pageIndex: 0, offsetInPage: 0
            )
            let parsed = await SentenceSegmenter.segment([block])
            player.load(parsed)
        }
    }

    private func saveAsMarkdown() {
        let panel = NSSavePanel()
        panel.title = "Save Scratchpad"
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "Scratchpad.md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// NSViewRepresentable wrapper around NSTextView — SwiftUI's native
/// `TextEditor` exists on macOS but it's less flexible: no easy way
/// to set a serif font, no pass-through of Markdown typing niceties
/// like smart quotes. Using an NSTextView directly gives us control
/// and matches the editor feel in the rest of the app (PDFs /
/// Markdown viewers all use NSTextView under the hood).
@MainActor
private struct ScratchpadEditor: NSViewRepresentable {
    @Binding var text: String
    let fontScale: Double

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        let baseSize = 16 * CGFloat(fontScale)
        textView.font = NSFont(name: "New York", size: baseSize) ?? NSFont.systemFont(ofSize: baseSize)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude
        )
        textView.string = text

        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = 1.35
        textView.defaultParagraphStyle = para
        textView.typingAttributes = [
            .font: textView.font ?? NSFont.systemFont(ofSize: baseSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: para,
        ]

        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        // Pick up font-scale changes (⌘+ / ⌘- or the slider). Reapply
        // only when the size actually drifted so per-keystroke updates
        // stay cheap.
        let desired = 16 * CGFloat(fontScale)
        if let current = textView.font, current.pointSize != desired {
            let next = NSFont(name: "New York", size: desired)
                ?? NSFont.systemFont(ofSize: desired)
            textView.font = next
            textView.typingAttributes[.font] = next
            if let storage = textView.textStorage, storage.length > 0 {
                storage.beginEditing()
                storage.addAttribute(
                    .font, value: next,
                    range: NSRange(location: 0, length: storage.length)
                )
                storage.endEditing()
            }
        }

        // Only overwrite if the host's text diverged from the view —
        // avoids blowing away the user's in-flight typing because
        // SwiftUI re-rendered the parent.
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

/// Read-only rendered view of the scratchpad's Markdown. Reuses
/// `MarkdownRenderer` — the same attributed-string pipeline the
/// MarkdownReaderView uses for .md files — so the Preview style
/// matches what a loaded Markdown document looks like.
@MainActor
private struct ScratchpadPreview: NSViewRepresentable {
    let markdown: String
    let activeSentence: Sentence?
    let spokenSubRange: NSRange?
    let fontScale: Double
    /// Double-click / "Read from here" callback. Kept optional so
    /// the scratchpad preview can be reused in contexts (screenshots,
    /// unit tests) that don't drive playback.
    let onReadFromOffset: ((Int) -> Void)?

    final class Coordinator {
        var lastRenderedSource: String?
        var lastRenderedScale: Double?
        var lastSentenceRange: NSRange?
        var lastSubRange: NSRange?
        var lastScrolledSentenceIndex: Int?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        // Use the same click-to-start subclass the Markdown and
        // EPUB readers use. Without it the scratchpad preview was a
        // passive NSTextView and the Speechify-style double-click
        // affordance silently did nothing.
        let textView = ClickableReaderTextView()
        textView.onReadFromOffset = onReadFromOffset
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude
        )

        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? ClickableReaderTextView,
              let storage = textView.textStorage else { return }
        // Re-bind the callback on every update so swapping the
        // host (e.g. a different scratchpad instance sharing the
        // same NSView) points clicks at the right player.
        textView.onReadFromOffset = onReadFromOffset
        // Only re-render when the source or font scale actually
        // changed — walking the markdown parser on every view update
        // is wasteful when the parent re-renders for unrelated reasons.
        if context.coordinator.lastRenderedSource != markdown
            || context.coordinator.lastRenderedScale != fontScale {
            let rendered = MarkdownRenderer.render(markdown, fontScale: fontScale)
            storage.setAttributedString(rendered)
            context.coordinator.lastRenderedSource = markdown
            context.coordinator.lastRenderedScale = fontScale
            context.coordinator.lastSentenceRange = nil
            context.coordinator.lastSubRange = nil
            context.coordinator.lastScrolledSentenceIndex = nil
        }

        applyScratchpadHighlight(
            to: textView,
            storage: storage,
            coordinator: context.coordinator,
            sentence: activeSentence,
            spokenSubRange: spokenSubRange
        )
    }
}

/// Same incremental-highlight strategy the Markdown / EPUB readers
/// use: bounded clears (only repaint the range we previously
/// touched) and scroll-only-on-sentence-change so word ticks from
/// the Whisper aligner don't yank the viewport on every update.
@MainActor
private func applyScratchpadHighlight(
    to textView: NSTextView,
    storage: NSTextStorage,
    coordinator: ScratchpadPreview.Coordinator,
    sentence: Sentence?,
    spokenSubRange: NSRange?
) {
    storage.beginEditing()

    if let last = coordinator.lastSubRange,
       NSMaxRange(last) <= storage.length {
        storage.removeAttribute(.backgroundColor, range: last)
    }
    if let last = coordinator.lastSentenceRange,
       NSMaxRange(last) <= storage.length {
        storage.removeAttribute(.backgroundColor, range: last)
    }

    guard let sentence else {
        coordinator.lastSentenceRange = nil
        coordinator.lastSubRange = nil
        storage.endEditing()
        return
    }

    let sentenceRange = NSRange(
        location: sentence.offsetInBlock,
        length: sentence.lengthInBlock
    )
    guard NSMaxRange(sentenceRange) <= storage.length else {
        coordinator.lastSentenceRange = nil
        coordinator.lastSubRange = nil
        storage.endEditing()
        return
    }

    let soft = NSColor(Color.readAloudTTSAccent).withAlphaComponent(0.25)
    storage.addAttribute(.backgroundColor, value: soft, range: sentenceRange)
    coordinator.lastSentenceRange = sentenceRange

    if let sub = spokenSubRange {
        let subOrigin = sentence.offsetInBlock + sub.location
        let subRange = NSRange(location: subOrigin, length: sub.length)
        if NSMaxRange(subRange) <= storage.length {
            let bright = NSColor(Color.readAloudTTSAccent).withAlphaComponent(0.55)
            storage.addAttribute(.backgroundColor, value: bright, range: subRange)
            coordinator.lastSubRange = subRange
        } else {
            coordinator.lastSubRange = nil
        }
    } else {
        coordinator.lastSubRange = nil
    }

    storage.endEditing()

    let currentIndex = sentence.offsetInBlock
    if coordinator.lastScrolledSentenceIndex != currentIndex {
        coordinator.lastScrolledSentenceIndex = currentIndex
        textView.scrollRangeToVisible(sentenceRange)
    }
}
