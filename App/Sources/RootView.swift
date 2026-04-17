import SwiftUI

/// The window's content owner. Wraps a `Library` sidebar around the
/// document detail view and keeps the drop edge live across both
/// columns so a new file can replace the current one at any time.
struct RootView: View {
    @State private var library = Library()
    @State private var document: DroppedDocument?
    @State private var selectedEntryID: LibraryEntry.ID?
    @State private var isTargeted = false

    var body: some View {
        NavigationSplitView {
            LibrarySidebarView(library: library, selectedID: $selectedEntryID)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            detail
        }
        .overlay(targetingHighlight)
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
            document = next
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
    }

    @ViewBuilder
    private func content(for document: DroppedDocument) -> some View {
        switch document.kind {
        case .pdf:
            PDFViewerView(url: document.url)
        case .markdown:
            MarkdownPlaceholderView(url: document.url)
        }
    }

    private var targetingHighlight: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.rheaAccent.opacity(isTargeted ? 0.65 : 0), lineWidth: 2)
            .padding(12)
            .allowsHitTesting(false)
    }

    private func adopt(_ next: DroppedDocument) {
        document = next
        library.record(url: next.url)
        // Sync sidebar selection to the just-recorded entry (top of list).
        selectedEntryID = library.entries.first?.id
    }
}
