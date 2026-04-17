import SwiftUI

/// Sidebar list of recently-opened documents. Click to reopen; the
/// owning `RootView` handles the bookmark resolution and swap.
struct LibrarySidebarView: View {
    @Bindable var library: Library
    @Binding var selectedID: LibraryEntry.ID?

    var body: some View {
        List(selection: $selectedID) {
            if library.entries.isEmpty {
                emptyRow
            } else {
                ForEach(library.entries) { entry in
                    row(for: entry).tag(entry.id)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Library")
    }

    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No documents yet")
                .font(RheaFont.ui(13))
                .foregroundStyle(.secondary)
            Text("Drop a PDF, Markdown, or EPUB file anywhere in the window.")
                .font(RheaFont.ui(11))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func row(for entry: LibraryEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.title)
                .font(RheaFont.ui(13))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(entry.lastOpened, style: .relative)
                .font(RheaFont.ui(11))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
