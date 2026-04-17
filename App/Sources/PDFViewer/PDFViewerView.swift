import SwiftUI
import PDFKit

/// Renders a PDF, runs text extraction + sentence segmentation,
/// hosts the per-document `SpeechPlayer`, and synchronises an
/// amber `PDFAnnotationHighlight` with the currently-spoken
/// sentence.
struct PDFViewerView: View {
    let url: URL

    @State private var loadResult: LoadResult = .loading
    @State private var blocks: [DocumentBlock] = []
    @State private var sentences: [Sentence] = []
    @State private var player = SpeechPlayer()

    var body: some View {
        Group {
            switch loadResult {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.rheaAccent)
            case .loaded(let document):
                PDFViewRepresentable(
                    document: document,
                    blocks: blocks,
                    activeSentence: activeSentence
                )
                .ignoresSafeArea()
                .overlay(alignment: .bottomLeading) { statusFooter(pageCount: document.pageCount) }
                .overlay(alignment: .bottomTrailing) {
                    PlaybackControlsView(player: player)
                        .padding(16)
                }
                .task(id: url) {
                    let extracted = await PDFTextExtractor.extract(document)
                    blocks = extracted
                    let parsed = await SentenceSegmenter.segment(extracted)
                    sentences = parsed
                    player.load(parsed)
                }
            case .failed:
                errorState
            }
        }
        .task(id: url) {
            loadResult = .loading
            blocks = []
            sentences = []
            player.stop()
            if let document = await PDFDocumentLoader.load(url: url) {
                loadResult = .loaded(document)
            } else {
                loadResult = .failed
            }
        }
        .onDisappear { player.stop() }
    }

    private var activeSentence: Sentence? {
        guard let index = player.state.sentenceIndex,
              index >= 0, index < sentences.count else { return nil }
        return sentences[index]
    }

    private func statusFooter(pageCount: Int) -> some View {
        let pages = pageCount == 1 ? "1 page" : "\(pageCount) pages"
        let text: String
        if blocks.isEmpty {
            text = "no extractable text · \(pages)"
        } else {
            let blockCount = blocks.count == 1 ? "1 block" : "\(blocks.count) blocks"
            let sentenceCount = sentences.count == 1 ? "1 sentence" : "\(sentences.count) sentences"
            text = "\(blockCount) · \(sentenceCount) · \(pages)"
        }
        return Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(12)
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

// MARK: - PDFView host with highlight coordination

private struct PDFViewRepresentable: NSViewRepresentable {
    let document: PDFDocument
    let blocks: [DocumentBlock]
    let activeSentence: Sentence?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = NSColor(Color.rheaSurface)
        view.document = document
        view.unregisterDraggedTypes()
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            removeHighlight(coordinator: context.coordinator)
            nsView.document = document
        }
        applyHighlight(view: nsView, coordinator: context.coordinator)
    }

    private func applyHighlight(view: PDFView, coordinator: Coordinator) {
        removeHighlight(coordinator: coordinator)

        guard let sentence = activeSentence,
              let selection = findSelection(for: sentence) else { return }

        let amber = NSColor(Color.rheaAccent).withAlphaComponent(0.4)
        for lineSelection in selection.selectionsByLine() {
            for page in lineSelection.pages {
                let bounds = lineSelection.bounds(for: page)
                let annotation = PDFAnnotation(
                    bounds: bounds,
                    forType: .highlight,
                    withProperties: nil
                )
                annotation.color = amber
                page.addAnnotation(annotation)
                coordinator.annotations.append((annotation, page))
            }
        }
        view.go(to: selection)
    }

    private func removeHighlight(coordinator: Coordinator) {
        for (annotation, page) in coordinator.annotations {
            page.removeAnnotation(annotation)
        }
        coordinator.annotations = []
    }

    /// Look up a `PDFSelection` for a sentence: prefer matches on
    /// the sentence's source page, fall back to the first match
    /// anywhere. Fragile against PDFs that hyphenate or normalize
    /// whitespace differently from `page.string` — improving this
    /// is a Month 3 polish item alongside Marker integration.
    private func findSelection(for sentence: Sentence) -> PDFSelection? {
        guard sentence.blockIndex < blocks.count else { return nil }
        let block = blocks[sentence.blockIndex]
        guard let page = document.page(at: block.pageIndex) else { return nil }
        let matches = document.findString(sentence.text, withOptions: [])
        return matches.first { $0.pages.contains(page) } ?? matches.first
    }

    final class Coordinator {
        var annotations: [(PDFAnnotation, PDFPage)] = []
    }
}
