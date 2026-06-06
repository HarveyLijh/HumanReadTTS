import SwiftUI
import AppKit
import os

/// Read-only viewer for plain-text files (`.txt`, `.text`, `.log`).
/// Reuses the shared `SpeechPlayer`/`SentenceSegmenter` plumbing the
/// other readers do — the file is loaded as a String, segmented, and
/// rendered in a single read-only NSTextView with sentence-level
/// highlight tracking. `ReaderSettings.fontScale` drives the displayed
/// point size so the same ⌘+ / ⌘- / ⌘0 shortcuts that resize the
/// Markdown reader apply unchanged.
struct TextReaderView: View {
    let url: URL
    let player: SpeechPlayer

    @State private var rawText: String = ""
    @State private var sentences: [Sentence] = []
    @State private var loadFailed = false
    @State private var errorMessage: String = ""
    @State private var search = SearchState()
    @State private var searchMatches: [NSRange] = []

    @Bindable private var readerSettings = ReaderSettings.shared

    private static let log = Logger(subsystem: "app.readaloudtts.mac", category: "text")

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ZStack(alignment: .topTrailing) {
                Group {
                    if loadFailed {
                        errorState
                    } else if rawText.isEmpty {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.readAloudTTSAccent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        PlainTextView(
                            text: rawText,
                            activeSentence: activeSentence,
                            spokenSubRange: player.spokenSubRange,
                            searchMatches: searchMatches,
                            currentMatchIndex: search.currentIndex,
                            fontScale: readerSettings.fontScale,
                            onReadFromOffset: handleReadFromOffset
                        )
                    }
                }

                if search.isPresented {
                    SearchBar(
                        state: search,
                        onSubmit: runSearch,
                        onNext: { advanceMatch(by: 1) },
                        onPrev: { advanceMatch(by: -1) },
                        onDismiss: dismissSearch
                    )
                    .padding(.top, 8)
                    .padding(.trailing, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .task(id: url) {
            await load()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppScene.findNotification)) { _ in
            presentSearch()
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "doc.plaintext")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(url.lastPathComponent)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            FontSizeControl()

            Button {
                presentSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Find in document (\u{2318}F)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
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
            // Try UTF-8 first; if the file is Latin-1 / UTF-16 the
            // decode fails and we fall back to a lossy UTF-8 read so
            // the user still sees something rather than a blank pane.
            let text: String
            if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
                text = utf8
            } else {
                let data = try Data(contentsOf: url)
                text = String(data: data, encoding: .isoLatin1)
                    ?? String(decoding: data, as: UTF8.self)
            }
            rawText = text
            loadFailed = false

            let block = DocumentBlock(text: text, pageIndex: 0, offsetInPage: 0)
            let parsed = await SentenceSegmenter.segment([block])
            sentences = parsed
            player.load(parsed)

            Self.log.info("TOTAL txt load \(ContinuousClock.now - started, privacy: .public) — \(parsed.count) sentences")
        } catch {
            Self.log.error("failed to read \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            rawText = ""
            sentences = []
            errorMessage = error.localizedDescription
            loadFailed = true
            player.load([])
        }
    }

    // MARK: - Search

    private func presentSearch() {
        if !search.isPresented {
            withAnimation(.easeOut(duration: 0.15)) {
                search.isPresented = true
            }
        }
        runSearch()
    }

    private func dismissSearch() {
        withAnimation(.easeOut(duration: 0.15)) {
            search.isPresented = false
        }
        searchMatches = []
        search.totalMatches = 0
        search.currentIndex = -1
    }

    private func runSearch() {
        let matches = TextSearcher.search(in: rawText, options: search)
        searchMatches = matches
        search.totalMatches = matches.count
        if matches.isEmpty {
            search.currentIndex = -1
        } else if search.currentIndex < 0 || search.currentIndex >= matches.count {
            search.currentIndex = 0
        }
    }

    private func advanceMatch(by delta: Int) {
        guard !searchMatches.isEmpty else { return }
        let next = (search.currentIndex + delta + searchMatches.count) % searchMatches.count
        search.currentIndex = next
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.readAloudTTSAccent)
            Text(errorMessage.isEmpty ? "Couldn't open \(url.lastPathComponent)." : errorMessage)
                .font(ReadAloudTTSFont.serif(18))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Drop another file to try again.")
                .font(ReadAloudTTSFont.ui(13))
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PlainTextView: NSViewRepresentable {
    let text: String
    let activeSentence: Sentence?
    let spokenSubRange: NSRange?
    let searchMatches: [NSRange]
    let currentMatchIndex: Int
    let fontScale: Double
    let onReadFromOffset: (Int) -> Void

    final class Coordinator {
        var lastText: String?
        var lastAppliedScale: Double?
        var lastSentenceRange: NSRange?
        var lastSubRange: NSRange?
        var lastScrolledSentenceIndex: Int?
        var lastSearchRanges: [NSRange] = []
        var lastCurrentSearchRange: NSRange?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(Color.readAloudTTSSurface)

        let textView = ClickableReaderTextView()
        textView.onReadFromOffset = onReadFromOffset
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.backgroundColor = NSColor(Color.readAloudTTSSurface)
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

        let textChanged = context.coordinator.lastText != text
        let scaleChanged = context.coordinator.lastAppliedScale != fontScale

        if textChanged || scaleChanged {
            let font = NSFont(name: "New York", size: 16 * CGFloat(fontScale))
                ?? NSFont.systemFont(ofSize: 16 * CGFloat(fontScale))
            let para = NSMutableParagraphStyle()
            para.lineHeightMultiple = 1.35
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: para,
            ]
            storage.beginEditing()
            storage.setAttributedString(NSAttributedString(string: text, attributes: attrs))
            storage.endEditing()

            context.coordinator.lastText = text
            context.coordinator.lastAppliedScale = fontScale
            context.coordinator.lastSentenceRange = nil
            context.coordinator.lastSubRange = nil
            context.coordinator.lastScrolledSentenceIndex = nil
            context.coordinator.lastSearchRanges = []
            context.coordinator.lastCurrentSearchRange = nil
        }

        applyHighlight(to: tv, storage: storage, coordinator: context.coordinator)
        applySearchHighlights(storage: storage, textView: tv, coordinator: context.coordinator)
    }

    private func applyHighlight(
        to textView: NSTextView,
        storage: NSTextStorage,
        coordinator: Coordinator
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

        guard let sentence = activeSentence else {
            coordinator.lastSentenceRange = nil
            coordinator.lastSubRange = nil
            storage.endEditing()
            // Re-paint search highlights, which the sentence wash may
            // have stomped on.
            repaintSearch(storage: storage, coordinator: coordinator)
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

        let soft = HighlightStyle.current.sentenceBand
        storage.addAttribute(.backgroundColor, value: soft, range: sentenceRange)
        coordinator.lastSentenceRange = sentenceRange

        if let sub = spokenSubRange {
            let subOrigin = sentence.offsetInBlock + sub.location
            let subRange = NSRange(location: subOrigin, length: sub.length)
            if NSMaxRange(subRange) <= storage.length {
                let bright = HighlightStyle.current.activeWord
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

    private func applySearchHighlights(
        storage: NSTextStorage,
        textView: NSTextView,
        coordinator: Coordinator
    ) {
        let prev = coordinator.lastSearchRanges
        let prevCurrent = coordinator.lastCurrentSearchRange
        guard prev != searchMatches
                || (currentMatchIndex >= 0 && currentMatchIndex < searchMatches.count
                    && prevCurrent != searchMatches[currentMatchIndex]) else {
            return
        }

        storage.beginEditing()
        for range in prev where NSMaxRange(range) <= storage.length {
            storage.removeAttribute(.underlineStyle, range: range)
            storage.removeAttribute(.underlineColor, range: range)
        }
        if let current = prevCurrent, NSMaxRange(current) <= storage.length {
            storage.removeAttribute(.backgroundColor, range: current)
        }
        let underline = NSColor(Color.readAloudTTSAccent).withAlphaComponent(0.7)
        for range in searchMatches where NSMaxRange(range) <= storage.length {
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            storage.addAttribute(.underlineColor, value: underline, range: range)
        }
        var current: NSRange?
        if currentMatchIndex >= 0, currentMatchIndex < searchMatches.count {
            current = searchMatches[currentMatchIndex]
            if let c = current, NSMaxRange(c) <= storage.length {
                storage.addAttribute(
                    .backgroundColor,
                    value: NSColor(Color.readAloudTTSAccent).withAlphaComponent(0.35),
                    range: c
                )
            }
        }
        storage.endEditing()
        coordinator.lastSearchRanges = searchMatches
        coordinator.lastCurrentSearchRange = current
        if let c = current {
            textView.scrollRangeToVisible(c)
        }
    }

    private func repaintSearch(
        storage: NSTextStorage,
        coordinator: Coordinator
    ) {
        guard !coordinator.lastSearchRanges.isEmpty else { return }
        storage.beginEditing()
        let underline = NSColor(Color.readAloudTTSAccent).withAlphaComponent(0.7)
        for range in coordinator.lastSearchRanges where NSMaxRange(range) <= storage.length {
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            storage.addAttribute(.underlineColor, value: underline, range: range)
        }
        storage.endEditing()
    }
}
