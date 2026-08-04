import SwiftUI
import AppKit
import os

/// Renders a `.docx` file's rich-text body as a single
/// `NSAttributedString` in the same NSTextView host the EPUB reader
/// uses. The Markdown reader's sentence-highlight pipeline works
/// unchanged because the underlying storage is identical — a flat
/// attributed string segmented into sentences by `SentenceSegmenter`.
struct DOCXReaderView: View {
    let url: URL
    let player: SpeechPlayer

    @State private var rendered: NSAttributedString = .init()
    @State private var sentences: [Sentence] = []
    @State private var loadFailed = false
    @State private var errorMessage: String = ""
    @State private var search = SearchState()
    @State private var searchMatches: [NSRange] = []
    @State private var followState = ReaderFollowState()

    @Bindable private var readerSettings = ReaderSettings.shared

    private static let log = Logger(subsystem: "app.humanreadtts.mac", category: "docx")

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ZStack(alignment: .topTrailing) {
                Group {
                    if loadFailed {
                        errorState
                    } else if rendered.length == 0 {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.readAloudTTSAccent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        DOCXTextView(
                            attributed: rendered,
                            activeSentence: activeSentence,
                            spokenSubRange: player.spokenSubRange,
                            searchMatches: searchMatches,
                            currentMatchIndex: search.currentIndex,
                            fontScale: readerSettings.fontScale,
                            followState: followState,
                            onReadFromOffset: handleReadFromOffset
                        )
                    }
                }
                .overlay(alignment: .bottom) {
                    JumpToCurrentButton(followState: followState, player: player)
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
        .onChange(of: player.state.isPlaying) { wasPlaying, isPlaying in
            if !wasPlaying, isPlaying { followState.jumpToCurrent() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppScene.findNotification)) { _ in
            presentSearch()
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "doc.richtext")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(url.deletingPathExtension().lastPathComponent)
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
        followState.jumpToCurrent()
        player.playFromSentence(idx)
    }

    private func load() async {
        followState.resumeFollowing()
        let started = ContinuousClock.now
        do {
            let attributed = try await DOCXLoader.load(url: url)
            rendered = attributed
            loadFailed = false

            let plain = attributed.string
            let block = DocumentBlock(text: plain, pageIndex: 0, offsetInPage: 0)
            let parsed = await SentenceSegmenter.segment([block])
            sentences = parsed
            player.load(parsed)

            Self.log.info("TOTAL docx load \(ContinuousClock.now - started, privacy: .public) — \(parsed.count) sentences")
        } catch let error as DOCXLoader.LoadError {
            errorMessage = error.errorDescription ?? "Couldn't read DOCX."
            loadFailed = true
            player.load([])
        } catch {
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
        let matches = TextSearcher.search(in: rendered.string, options: search)
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
            Text(errorMessage.isEmpty ? "Couldn't read the DOCX." : errorMessage)
                .font(HumanReadTTSFont.serif(18))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Drop another file to try again.")
                .font(HumanReadTTSFont.ui(13))
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DOCXTextView: NSViewRepresentable {
    let attributed: NSAttributedString
    let activeSentence: Sentence?
    let spokenSubRange: NSRange?
    let searchMatches: [NSRange]
    let currentMatchIndex: Int
    let fontScale: Double
    let followState: ReaderFollowState
    let onReadFromOffset: (Int) -> Void

    final class Coordinator {
        var lastAttributedIdentity: ObjectIdentifier?
        var lastAppliedFontScale: Double?
        var lastSentenceRange: NSRange?
        var lastSubRange: NSRange?
        var lastScrolledSentenceIndex: Int?
        var lastSearchRanges: [NSRange] = []
        var lastCurrentSearchRange: NSRange?
        let scrollObserver = ReaderScrollObserver()
        var lastHandledJumpToken = 0
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
        textView.isRichText = true
        textView.backgroundColor = NSColor(Color.readAloudTTSSurface)
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 32, height: 24)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude
        )

        scroll.documentView = textView
        context.coordinator.scrollObserver.attach(to: scroll) { [followState] in
            followState.userDidScroll()
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? ClickableReaderTextView,
              let storage = tv.textStorage else { return }

        tv.onReadFromOffset = onReadFromOffset

        let identity = ObjectIdentifier(attributed)
        let identityChanged = context.coordinator.lastAttributedIdentity != identity
        if identityChanged {
            storage.setAttributedString(attributed)
            context.coordinator.lastAttributedIdentity = identity
            context.coordinator.lastAppliedFontScale = nil
            context.coordinator.lastSentenceRange = nil
            context.coordinator.lastSubRange = nil
            context.coordinator.lastScrolledSentenceIndex = nil
            context.coordinator.lastSearchRanges = []
            context.coordinator.lastCurrentSearchRange = nil
        }

        // Apply font scale by walking `.font` runs and rescaling. The
        // DOCX loader emits per-run fonts (heading sizes, bold/italic
        // variants) so we scale in-place to preserve those choices.
        let appliedScale = context.coordinator.lastAppliedFontScale ?? 1.0
        if appliedScale != fontScale {
            applyFontScale(to: storage, from: appliedScale, to: fontScale)
            context.coordinator.lastAppliedFontScale = fontScale
        }

        applyHighlight(to: tv, storage: storage, coordinator: context.coordinator)
        applySearchHighlights(storage: storage, textView: tv, coordinator: context.coordinator)
        handleJumpRequest(textView: tv, storage: storage, coordinator: context.coordinator)
    }

    /// Scroll back to the current sentence when the user taps "jump to
    /// current". Bridged from SwiftUI via `followState.jumpToken`.
    private func handleJumpRequest(
        textView: NSTextView,
        storage: NSTextStorage,
        coordinator: Coordinator
    ) {
        guard coordinator.lastHandledJumpToken != followState.jumpToken else { return }
        coordinator.lastHandledJumpToken = followState.jumpToken
        guard let sentence = activeSentence else { return }
        let range = NSRange(location: sentence.offsetInBlock, length: sentence.lengthInBlock)
        guard NSMaxRange(range) <= storage.length else { return }
        coordinator.lastScrolledSentenceIndex = sentence.offsetInBlock
        textView.scrollRangeToVisible(range)
    }

    private func applyFontScale(
        to storage: NSTextStorage,
        from current: Double,
        to target: Double
    ) {
        guard storage.length > 0, current > 0, target > 0 else { return }
        let ratio = CGFloat(target / current)
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
            guard let font = value as? NSFont else { return }
            let scaled = NSFontManager.shared.convert(
                font, toSize: font.pointSize * ratio
            )
            storage.addAttribute(.font, value: scaled, range: range)
        }
        storage.endEditing()
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
        if followState.isFollowing, coordinator.lastScrolledSentenceIndex != currentIndex {
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
}
