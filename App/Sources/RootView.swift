import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// The window's content owner. Wraps a `Library` sidebar around the
/// document detail view and keeps the drop edge live across both
/// columns so a new file can replace the current one at any time.
///
/// `SpeechPlayer` lives here, not inside the per-format viewers, so
/// PDFs and Markdown share one playback instance and the controls
/// can sit at the window level rather than re-implemented per
/// viewer. Changing documents stops the previous playback before
/// the new viewer's `task` re-loads sentences.
struct RootView: View {
    @Environment(\.openWindow) private var openWindow

    @State private var library = Library()
    @State private var document: DroppedDocument?
    @State private var selectedEntryID: LibraryEntry.ID?
    @State private var isTargeted = false
    @State private var player = SpeechPlayer()
    @State private var exporter = ExportCoordinator.shared
    @State private var fallbackBannerVisible = false
    @State private var fallbackBannerText: String = ""
    @State private var fallbackDismissTask: Task<Void, Never>?
    @State private var undoBannerVisible = false
    @State private var undoBannerText: String = ""
    @State private var undoPrevious: String?
    @State private var undoDismissTask: Task<Void, Never>?
    /// Resume index consumed by the content viewer on next load.
    /// Set from the library when adopting a document; cleared once
    /// the viewer has applied it so a re-render won't snap playback
    /// back. See `content(for:)` and `seekPaused` on the player.
    @State private var pendingResumeIndex: Int?
    /// Active scratchpad text. Non-nil means the user picked File →
    /// New; the detail pane swaps the viewer for an in-app editor.
    /// Dropping a real document or picking a library entry resets
    /// this to nil so the reader takes back over.
    @State private var scratchpadText: String?

    var body: some View {
        NavigationSplitView {
            LibrarySidebarView(library: library, selectedID: $selectedEntryID)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            detail
        }
        .overlay(targetingHighlight)
        .overlay(alignment: .top) {
            if case .running(let fraction) = exporter.state {
                exportProgressBanner(fraction: fraction)
            } else if case .failed(let message) = exporter.state {
                exportErrorBanner(message: message)
            } else if fallbackBannerVisible {
                fallbackBanner
            } else if undoBannerVisible {
                undoBanner
            }
        }
        .onChange(of: player.lastSwitchEvent) { _, event in
            handleSwitchEvent(event)
        }
        .onChange(of: player.state.sentenceIndex) { _, newIndex in
            recordPosition(for: newIndex)
        }
        .onChange(of: player.sentences) { _, newSentences in
            // Viewer finished loading — apply any pending resume
            // index. We trigger on the transition out of "empty"
            // rather than eagerly, because the viewer clears the
            // queue on document change and re-fills asynchronously.
            if !newSentences.isEmpty {
                applyPendingResume()
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, let next = DroppedDocument(url: url) else {
                return false
            }
            adopt(next)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .onChange(of: selectedEntryID) { _, newID in
            guard let newID,
                  let entry = library.entries.first(where: { $0.id == newID }),
                  let url = library.resolve(entry),
                  let next = DroppedDocument(url: url) else { return }
            player.stop()
            scratchpadText = nil
            pendingResumeIndex = library.savedPosition(for: url)
            document = next
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .rheaOpenURL)
        ) { note in
            // Routed via `AppDelegateShim.application(_:open:)` so
            // `open -a Rhea file.pdf` and Finder double-clicks swap
            // the document in the existing window rather than
            // triggering `WindowGroup` to spawn a new scene.
            guard let url = note.userInfo?["url"] as? URL,
                  let next = DroppedDocument(url: url) else { return }
            adopt(next)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: AppScene.exportNotification)
        ) { _ in
            startExport()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: AppScene.showExportsNotification)
        ) { _ in
            openWindow(id: "exports")
        }
        .onReceive(
            NotificationCenter.default.publisher(for: AppScene.playPauseNotification)
        ) { _ in
            player.togglePlayPause()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: AppScene.nextSentenceNotification)
        ) { _ in
            player.nextSentence()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: AppScene.prevSentenceNotification)
        ) { _ in
            player.previousSentence()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: AppScene.openFileNotification)
        ) { _ in
            promptForOpenFile()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: AppScene.newScratchpadNotification)
        ) { _ in
            openScratchpad()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: AppScene.speedFasterNotification)
        ) { _ in
            let current = SpeechSettings.shared.rate
            player.setRate(min(4.0, (current + 0.1).roundedToStep(0.05)))
        }
        .onReceive(
            NotificationCenter.default.publisher(for: AppScene.speedSlowerNotification)
        ) { _ in
            let current = SpeechSettings.shared.rate
            player.setRate(max(0.5, (current - 0.1).roundedToStep(0.05)))
        }
        .animation(.easeOut(duration: 0.18), value: isTargeted)
        .animation(.easeOut(duration: 0.18), value: document)
    }

    @ViewBuilder
    private var detail: some View {
        ZStack {
            Color.rheaSurface.ignoresSafeArea()

            if scratchpadText != nil {
                ScratchpadView(
                    player: player,
                    text: Binding(
                        get: { scratchpadText ?? "" },
                        set: { scratchpadText = $0 }
                    )
                )
            } else if let document {
                content(for: document)
            } else {
                DropTargetView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // safeAreaInset reserves layout space for the HUD so
            // the document never scrolls underneath it. An overlay
            // would visually cover the last line of text, which is
            // exactly what we hit when the window got wider.
            if document != nil || scratchpadText != nil {
                PlaybackTransportView(player: player)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func content(for document: DroppedDocument) -> some View {
        switch document.kind {
        case .pdf:
            PDFViewerView(url: document.url, player: player)
        case .markdown:
            MarkdownReaderView(url: document.url, player: player)
        case .epub:
            EPUBReaderView(url: document.url, player: player)
        }
    }

    private var targetingHighlight: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.rheaAccent.opacity(isTargeted ? 0.65 : 0), lineWidth: 2)
            .padding(12)
            .allowsHitTesting(false)
    }

    private func adopt(_ next: DroppedDocument) {
        player.stop()
        scratchpadText = nil
        // Look up resume position BEFORE `library.record(url:)` moves
        // the entry to the top — the record call preserves the
        // existing `lastSentenceIndex`, so both orderings work, but
        // reading up-front keeps intent obvious.
        pendingResumeIndex = library.savedPosition(for: next.url)
        document = next
        library.record(url: next.url)
        selectedEntryID = library.entries.first?.id
    }

    private func openScratchpad() {
        player.stop()
        document = nil
        selectedEntryID = nil
        // Preserve existing scratchpad text if the user hits ⌘N a
        // second time — "New" shouldn't nuke in-progress work. A
        // blank scratchpad is reachable by selecting all + delete.
        if scratchpadText == nil {
            scratchpadText = ""
        }
    }

    /// Observe sentence-index changes and persist them to the
    /// library entry backing the current document. Fires often (per
    /// sentence advance) but `Library.recordPosition` guards against
    /// no-op writes so UserDefaults churn is bounded.
    private func recordPosition(for sentenceIndex: Int?) {
        guard let sentenceIndex, let document else { return }
        library.recordPosition(
            url: document.url, sentenceIndex: sentenceIndex
        )
    }

    /// Handed to viewers. Once the viewer loads its sentences into
    /// the player, this seeks the player to the saved paused index
    /// and clears `pendingResumeIndex` so the same resume doesn't
    /// re-apply on rerender.
    private func applyPendingResume() {
        guard let idx = pendingResumeIndex else { return }
        player.seekPaused(to: idx)
        pendingResumeIndex = nil
    }

    // MARK: export banners

    private func exportProgressBanner(fraction: Double) -> some View {
        VStack(spacing: 4) {
            Text("Exporting audiobook…")
                .font(RheaFont.ui(12))
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .frame(width: 260)
            Text(String(format: "%.0f%%", fraction * 100))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(.top, 12)
    }

    /// Toast-style warning for engine fallbacks. Auto-dismisses
    /// after ~2s so the user knows WHY their chosen neural voice
    /// is being served by the system voice instead — without
    /// clogging the transport with a permanent banner.
    private var fallbackBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.slash")
                .foregroundStyle(.orange)
            Text(fallbackBannerText)
                .font(RheaFont.ui(12))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.orange.opacity(0.5), lineWidth: 0.5))
        .padding(.top, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func handleSwitchEvent(_ event: SpeechPlayer.SwitchEvent?) {
        guard let event else { return }
        switch event.kind {
        case .engineFallback(let requested, _):
            fallbackBannerText = "\(requested) unavailable — using system voice."
            withAnimation(.easeOut(duration: 0.2)) {
                fallbackBannerVisible = true
            }
            fallbackDismissTask?.cancel()
            fallbackDismissTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    fallbackBannerVisible = false
                }
                // Also clear the sticky event — the chip returns to
                // the user's chosen voice. If the next sentence still
                // falls back, a fresh event + banner re-appear.
                player.dismissSwitchEvent()
            }
        case .voiceChanged(let previous, let current):
            // Undo toast: the chip already shows the new voice; the
            // banner is a non-modal "Switched to …" confirmation with
            // an Undo action that reverts to the previous selection.
            // Auto-dismiss at 4s — a bit longer than the fallback
            // warning so the Undo button is actually reachable.
            undoPrevious = previous
            undoBannerText = "Switched to \(displayName(for: current))"
            withAnimation(.easeOut(duration: 0.2)) {
                undoBannerVisible = true
            }
            undoDismissTask?.cancel()
            undoDismissTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    undoBannerVisible = false
                }
                player.dismissSwitchEvent()
            }
        }
    }

    private var undoBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(Color.rheaAccent)
            Text(undoBannerText)
                .font(RheaFont.ui(12))
                .foregroundStyle(.primary)
            Button("Undo") {
                undoDismissTask?.cancel()
                withAnimation(.easeOut(duration: 0.2)) {
                    undoBannerVisible = false
                }
                player.setVoice(undoPrevious)
                undoPrevious = nil
            }
            .buttonStyle(.plain)
            .font(RheaFont.ui(12).weight(.semibold))
            .foregroundStyle(Color.rheaAccent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
        .padding(.top, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Resolves a voice identifier to a human-readable label for the
    /// undo toast. Matches the transport chip's label logic so the
    /// two always agree on what to call the voice.
    private func displayName(for identifier: String?) -> String {
        guard let id = identifier else { return "Auto" }
        if id.hasPrefix("kokoro:") {
            return KokoroEngine.shared.voices
                .first(where: { $0.id == id })?.displayName ?? "Kokoro"
        }
        if id.hasPrefix("qwen:") {
            return QwenEngine.shared.voices
                .first(where: { $0.id == id })?.displayName ?? "Qwen"
        }
        return AVSpeechSynthesisVoice(identifier: id)?.name ?? "System"
    }

    private func exportErrorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.rheaAccent)
            Text(message)
                .font(RheaFont.ui(12))
            Button("Dismiss") { exporter.dismissAlert() }
                .buttonStyle(.plain)
                .font(RheaFont.ui(12))
                .foregroundStyle(Color.rheaAccent)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(.top, 12)
    }

    /// Present NSOpenPanel for the File → Open File… menu (⌘O).
    private func promptForOpenFile() {
        let panel = NSOpenPanel()
        panel.title = "Open a PDF, Markdown, or EPUB"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .epub]
        // Also allow .md / .markdown — allowedContentTypes accepts UTType
        if let md = UTType(filenameExtension: "md") {
            panel.allowedContentTypes.append(md)
        }
        if let markdown = UTType(filenameExtension: "markdown") {
            panel.allowedContentTypes.append(markdown)
        }
        if panel.runModal() == .OK,
           let url = panel.url,
           let next = DroppedDocument(url: url) {
            adopt(next)
        }
    }

    /// Called from the File → Export Audiobook menu command.
    func startExport() {
        let sentences = currentSentences()
        let suggestion = document?.url.deletingPathExtension().lastPathComponent ?? "Rhea Export"
        exporter.exportWithPrompt(sentences: sentences, suggestedName: suggestion)
    }

    private func currentSentences() -> [Sentence] {
        player.sentences
    }
}

private extension Double {
    func roundedToStep(_ step: Double) -> Double {
        (self / step).rounded() * step
    }
}
