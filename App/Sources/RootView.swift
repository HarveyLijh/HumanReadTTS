import SwiftUI
import AppKit
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
    @State private var library = Library()
    @State private var document: DroppedDocument?
    @State private var selectedEntryID: LibraryEntry.ID?
    @State private var isTargeted = false
    @State private var player = SpeechPlayer()
    @State private var exporter = ExportCoordinator()
    @State private var fallbackBannerVisible = false
    @State private var fallbackBannerText: String = ""
    @State private var fallbackDismissTask: Task<Void, Never>?

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
            }
        }
        .onChange(of: player.lastSwitchEvent) { _, event in
            handleSwitchEvent(event)
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

            if let document {
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
            if document != nil {
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
        document = next
        library.record(url: next.url)
        selectedEntryID = library.entries.first?.id
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
        case .voiceChanged:
            // Handled by transport (chip label + icon update); no banner.
            break
        }
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
