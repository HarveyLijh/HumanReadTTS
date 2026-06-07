import SwiftUI
import AppKit
import os

/// Reads an image file by running on-device OCR and presenting the
/// recognized text like any other document: segmented into sentences,
/// highlighted during playback, clickable to read from a point, and
/// styled by the reading typography/theme. Reuses ``PlainTextView`` so
/// the recognized text behaves exactly like a plain-text document.
struct ImageOCRReaderView: View {
    let url: URL
    let player: SpeechPlayer

    @State private var rawText: String = ""
    @State private var sentences: [Sentence] = []
    @State private var status: Status = .recognizing
    @State private var errorMessage: String = ""
    @State private var search = SearchState()
    @State private var searchMatches: [NSRange] = []
    @State private var followState = ReaderFollowState()

    @Bindable private var readerSettings = ReaderSettings.shared

    private enum Status { case recognizing, ready, empty, failed }

    private static let log = Logger(subsystem: "app.readaloudtts.mac", category: "ocr")

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ZStack(alignment: .topTrailing) {
                Group {
                    switch status {
                    case .recognizing:
                        recognizingState
                    case .failed:
                        messageState(icon: "exclamationmark.triangle",
                                     text: errorMessage.isEmpty ? "Couldn’t read \(url.lastPathComponent)." : errorMessage)
                    case .empty:
                        messageState(icon: "text.viewfinder",
                                     text: "No readable text was found in this image.")
                    case .ready:
                        PlainTextView(
                            text: rawText,
                            activeSentence: activeSentence,
                            spokenSubRange: player.spokenSubRange,
                            searchMatches: searchMatches,
                            currentMatchIndex: search.currentIndex,
                            fontScale: readerSettings.fontScale,
                            typography: ReaderTypography(from: readerSettings),
                            readingTheme: readerSettings.readingTheme,
                            followState: followState,
                            onReadFromOffset: handleReadFromOffset
                        )
                    }
                }
                .lineFocus(enabled: readerSettings.lineFocusEnabled,
                           bandHeight: readerSettings.lineFocusHeight)
                .overlay(alignment: .bottom) {
                    JumpToCurrentButton(followState: followState, player: player)
                }

                if search.isPresented, status == .ready {
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
            if status == .ready { presentSearch() }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(url.lastPathComponent)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("OCR")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.secondary.opacity(0.14)))

            Spacer()

            FontSizeControl()

            Button {
                presentSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .disabled(status != .ready)
            .help("Find in document (\u{2318}F)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var recognizingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(Color.readAloudTTSAccent)
            Text("Recognizing text…")
                .font(ReadAloudTTSFont.ui(13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func messageState(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.readAloudTTSAccent)
            Text(text)
                .font(ReadAloudTTSFont.serif(18))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
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
        status = .recognizing
        let started = ContinuousClock.now
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            errorMessage = "This image couldn’t be opened."
            status = .failed
            player.load([])
            return
        }

        do {
            let recognized = try await OCRService.shared.recognizeText(
                in: cgImage,
                languages: SpeechSettings.shared.ocrRecognitionLanguages
            )
            rawText = recognized
            let block = DocumentBlock(text: recognized, pageIndex: 0, offsetInPage: 0)
            let parsed = await SentenceSegmenter.segment([block], reflowLineWraps: true)
            sentences = parsed
            player.load(parsed)
            status = .ready
            Self.log.info("OCR load \(ContinuousClock.now - started, privacy: .public) — \(parsed.count) sentences")
        } catch OCRError.noText {
            rawText = ""
            sentences = []
            player.load([])
            status = .empty
        } catch {
            errorMessage = error.localizedDescription
            sentences = []
            player.load([])
            status = .failed
        }
    }

    // MARK: - Search

    private func presentSearch() {
        if !search.isPresented {
            withAnimation(.easeOut(duration: 0.15)) { search.isPresented = true }
        }
        runSearch()
    }

    private func dismissSearch() {
        withAnimation(.easeOut(duration: 0.15)) { search.isPresented = false }
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
        search.currentIndex = (search.currentIndex + delta + searchMatches.count) % searchMatches.count
    }
}
