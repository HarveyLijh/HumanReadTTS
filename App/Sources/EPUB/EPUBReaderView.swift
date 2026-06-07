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
    @State private var followState = ReaderFollowState()

    @Bindable private var readerSettings = ReaderSettings.shared

    private static let log = Logger(subsystem: "app.readaloudtts.mac", category: "epub")

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Group {
                if loadFailed {
                    errorState
                } else if rendered.length == 0 {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.readAloudTTSAccent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EPUBTextView(
                        attributed: rendered,
                        activeSentence: activeSentence,
                        spokenSubRange: player.spokenSubRange,
                        fontScale: readerSettings.fontScale,
                        followState: followState,
                        onReadFromOffset: handleReadFromOffset
                    )
                }
            }
            .overlay(alignment: .bottom) {
                JumpToCurrentButton(followState: followState, player: player)
            }
        }
        .task(id: url) {
            await load()
        }
        .onChange(of: player.state.isPlaying) { wasPlaying, isPlaying in
            if !wasPlaying, isPlaying { followState.jumpToCurrent() }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "book.closed")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(url.deletingPathExtension().lastPathComponent)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            FontSizeControl()
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
                .foregroundStyle(Color.readAloudTTSAccent)
            Text(errorMessage.isEmpty ? "Couldn't read the EPUB." : errorMessage)
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

private struct EPUBTextView: NSViewRepresentable {
    let attributed: NSAttributedString
    let activeSentence: Sentence?
    let spokenSubRange: NSRange?
    let fontScale: Double
    let followState: ReaderFollowState
    let onReadFromOffset: (Int) -> Void

    final class Coordinator {
        var lastAttributedIdentity: ObjectIdentifier?
        var lastAppliedFontScale: Double?
        var lastSentenceRange: NSRange?
        var lastSubRange: NSRange?
        var lastScrolledSentenceIndex: Int?
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
        }

        // Apply the user's font scale by walking every `.font` run and
        // multiplying its point size. We track the last-applied scale
        // so a no-op tick (e.g. a highlight repaint) doesn't restyle
        // the storage. EPUB documents bring their own fonts per run,
        // so scaling in-place preserves the publisher's intent (italic
        // emphasis, monospace code, etc.) — only the size shifts.
        let appliedScale = context.coordinator.lastAppliedFontScale ?? 1.0
        if appliedScale != fontScale {
            applyFontScale(
                to: storage,
                from: appliedScale,
                to: fontScale
            )
            context.coordinator.lastAppliedFontScale = fontScale
        }

        applyHighlight(to: tv, storage: storage, coordinator: context.coordinator)
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

    /// Walks every `.font` run and rescales it by `target / current`.
    /// Tracking the last-applied scale lets us multiply a delta
    /// instead of re-deriving sizes from a base attributed string —
    /// which we'd otherwise have to keep in memory in addition to
    /// the live storage.
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

    /// Same incremental-highlight strategy as the Markdown reader:
    /// bounded clears + scroll-only-on-sentence-change, so the
    /// Whisper aligner's word-level ticks stop thrashing the whole
    /// text storage and the user's manual scrolling doesn't get
    /// yanked back on every update.
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
}
