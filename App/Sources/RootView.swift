import SwiftUI

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
            document = next
        }
        .onOpenURL { url in
            // Covers Finder "Open With", `open -a Rhea file.pdf`,
            // and any other LaunchServices dispatch. Reuses the
            // same drop/adopt path as drag-drop.
            guard let next = DroppedDocument(url: url) else { return }
            adopt(next)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: AppScene.exportNotification)
        ) { _ in
            startExport()
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
        .overlay(alignment: .bottomTrailing) {
            if document != nil {
                PlaybackControlsView(player: player)
                    .padding(16)
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
