import SwiftUI

/// The window's content owner: holds the current `DroppedDocument`,
/// routes `.pdf` files to the PDF viewer and `.md` files to the
/// markdown placeholder, and keeps the drop edge live across all
/// states so a new file can replace the current one at any time.
struct RootView: View {
    @State private var document: DroppedDocument?
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            Color.rheaSurface.ignoresSafeArea()

            Group {
                if let document {
                    content(for: document)
                } else {
                    DropTargetView()
                }
            }
        }
        .overlay(targetingHighlight)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, let next = DroppedDocument(url: url) else {
                return false
            }
            document = next
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .animation(.easeOut(duration: 0.18), value: isTargeted)
        .animation(.easeOut(duration: 0.18), value: document)
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
}
