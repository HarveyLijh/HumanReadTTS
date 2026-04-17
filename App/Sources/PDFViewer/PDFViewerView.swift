import SwiftUI
import PDFKit

/// Renders a PDF using PDFKit's native `PDFView`. Async-loads the
/// document via `PDFDocumentLoader`, shows a quiet progress indicator
/// while it parses, and falls back to a warm error state for files
/// PDFKit can't decode (corrupt, encrypted, mislabeled).
struct PDFViewerView: View {
    let url: URL

    @State private var loadResult: LoadResult = .loading

    var body: some View {
        Group {
            switch loadResult {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.rheaAccent)
            case .loaded(let document):
                PDFViewRepresentable(document: document)
                    .ignoresSafeArea()
            case .failed:
                errorState
            }
        }
        .task(id: url) {
            loadResult = .loading
            if let document = await PDFDocumentLoader.load(url: url) {
                loadResult = .loaded(document)
            } else {
                loadResult = .failed
            }
        }
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.rheaAccent)
            Text("Couldn't open \(url.lastPathComponent).")
                .font(RheaFont.serif(18))
                .foregroundStyle(.primary)
            Text("Drop another file to try again.")
                .font(RheaFont.ui(13))
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }

    enum LoadResult: Equatable {
        case loading
        case loaded(PDFDocument)
        case failed
    }
}

private struct PDFViewRepresentable: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        // Theme just the background to Color.rheaSurface; leave PDFKit's
        // scrollbars and page-shadow defaults untouched. Apple territory.
        view.backgroundColor = NSColor(Color.rheaSurface)
        view.document = document
        // PDFView registers itself as an NSDraggingDestination at init
        // and silently eats drag events for files it can't open (e.g.
        // a .md dropped on top of a loaded PDF). Unregister so the
        // SwiftUI .dropDestination on RootView gets every drag.
        view.unregisterDraggedTypes()
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
        }
    }
}
