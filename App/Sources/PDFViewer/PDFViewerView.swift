import SwiftUI
import PDFKit

/// Renders a PDF, runs text extraction + sentence segmentation,
/// pushes the segmented sentence queue into the shared
/// `SpeechPlayer`, and synchronises an amber `PDFAnnotationHighlight`
/// with the currently-spoken sentence.
struct PDFViewerView: View {
    let url: URL
    let player: SpeechPlayer

    @State private var loadResult: LoadResult = .loading
    @State private var blocks: [DocumentBlock] = []
    @State private var sentences: [Sentence] = []

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
                    activeSentence: activeSentence,
                    spokenSubRange: player.spokenSubRange
                )
                .ignoresSafeArea()
                .overlay(alignment: .bottomLeading) { statusFooter(pageCount: document.pageCount) }
                .task(id: url) {
                    let extracted = await PDFTextExtractor.extract(
                        document,
                        skipFigureCaptions: SpeechSettings.shared.skipFigureCaptions
                    )
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
            if let document = await PDFDocumentLoader.load(url: url) {
                loadResult = .loaded(document)
            } else {
                loadResult = .failed
            }
        }
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
    let spokenSubRange: NSRange?

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
              let sentenceSelection = selection(for: sentence) else { return }

        // Sentence-wide soft wash.
        let soft = NSColor(Color.rheaAccent).withAlphaComponent(0.25)
        for lineSelection in sentenceSelection.selectionsByLine() {
            for page in lineSelection.pages {
                let bounds = lineSelection.bounds(for: page)
                let annotation = PDFAnnotation(
                    bounds: bounds,
                    forType: .highlight,
                    withProperties: nil
                )
                annotation.color = soft
                page.addAnnotation(annotation)
                coordinator.annotations.append((annotation, page))
            }
        }

        // Brighter word-level sub-highlight on top for system voices
        // that deliver willSpeakRange callbacks. The range is in the
        // *spoken* text; for PDFs the rendered and spoken text lines
        // up in the common case (no transformations), so mapping
        // sentence.offsetInBlock + sub.location into the page works.
        if let sub = spokenSubRange,
           let wordSelection = wordSelection(for: sentence, subRange: sub) {
            let bright = NSColor(Color.rheaAccent).withAlphaComponent(0.55)
            for lineSelection in wordSelection.selectionsByLine() {
                for page in lineSelection.pages {
                    let bounds = lineSelection.bounds(for: page)
                    let annotation = PDFAnnotation(
                        bounds: bounds,
                        forType: .highlight,
                        withProperties: nil
                    )
                    annotation.color = bright
                    page.addAnnotation(annotation)
                    coordinator.annotations.append((annotation, page))
                }
            }
        }

        view.go(to: sentenceSelection)
    }

    private func wordSelection(for sentence: Sentence, subRange: NSRange) -> PDFSelection? {
        guard sentence.blockIndex < blocks.count else { return nil }
        let block = blocks[sentence.blockIndex]
        guard let page = document.page(at: block.pageIndex) else { return nil }
        let pageOffset = block.offsetInPage + sentence.offsetInBlock + subRange.location
        let range = NSRange(location: pageOffset, length: subRange.length)
        return page.selection(for: range)
    }

    private func removeHighlight(coordinator: Coordinator) {
        for (annotation, page) in coordinator.annotations {
            page.removeAnnotation(annotation)
        }
        coordinator.annotations = []
    }

    /// O(1) sentence → `PDFSelection` lookup. Uses
    /// `PDFPage.selection(for: NSRange)` against page-relative UTF-16
    /// offsets that the extractor recorded during `page.string`
    /// extraction. Avoids the per-state-change `PDFDocument.findString`
    /// scan that stalled large documents.
    private func selection(for sentence: Sentence) -> PDFSelection? {
        guard sentence.blockIndex < blocks.count else { return nil }
        let block = blocks[sentence.blockIndex]
        guard let page = document.page(at: block.pageIndex) else { return nil }
        let pageOffset = block.offsetInPage + sentence.offsetInBlock
        let range = NSRange(location: pageOffset, length: sentence.lengthInBlock)
        return page.selection(for: range)
    }

    final class Coordinator {
        var annotations: [(PDFAnnotation, PDFPage)] = []
    }
}
