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
                    spokenSubRange: player.spokenSubRange,
                    onReadFromLocation: handleReadFromLocation
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

    /// The PDFView host reports (pageIndex, pageOffset) for the
    /// character under the mouse. Look up the enclosing sentence
    /// and seek playback there.
    private func handleReadFromLocation(_ location: PDFClickLocation) {
        guard let idx = ReaderHitTester.sentenceIndex(
            forPageOffset: location.pageOffset,
            pageIndex: location.pageIndex,
            sentences: sentences,
            blocks: blocks
        ) else { return }
        player.playFromSentence(idx)
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

struct PDFClickLocation: Equatable {
    let pageIndex: Int
    /// UTF-16 offset into the page's extracted `page.string`.
    let pageOffset: Int
}

private struct PDFViewRepresentable: NSViewRepresentable {
    let document: PDFDocument
    let blocks: [DocumentBlock]
    let activeSentence: Sentence?
    let spokenSubRange: NSRange?
    let onReadFromLocation: (PDFClickLocation) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = ClickablePDFView()
        view.onReadFromLocation = onReadFromLocation
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = NSColor(Color.rheaSurface)
        view.document = document
        view.unregisterDraggedTypes()
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if let clickable = nsView as? ClickablePDFView {
            clickable.onReadFromLocation = onReadFromLocation
        }
        if nsView.document !== document {
            removeHighlight(coordinator: context.coordinator)
            nsView.document = document
        }
        applyHighlight(view: nsView, coordinator: context.coordinator)
    }

    private func applyHighlight(view: PDFView, coordinator: Coordinator) {
        // The sentence wash rarely needs to change — it only needs
        // a rebuild when the active sentence changes, not on every
        // word-level subRange tick from the Whisper aligner. Rebuild
        // the sub-highlight separately so word ticks are cheap.
        let sentenceID = activeSentence.map {
            SentenceKey(blockIndex: $0.blockIndex, offsetInBlock: $0.offsetInBlock)
        }
        let subRangeChanged = coordinator.lastSubRange != spokenSubRange
        let sentenceChanged = coordinator.lastSentenceKey != sentenceID

        if sentenceChanged {
            removeSentenceAnnotations(coordinator: coordinator)
            removeSubAnnotations(coordinator: coordinator)
            coordinator.lastSentenceKey = sentenceID
            coordinator.lastSubRange = nil

            if let sentence = activeSentence,
               let sentenceSelection = selection(for: sentence) {
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
                        coordinator.sentenceAnnotations.append((annotation, page))
                    }
                }
                // Only scroll on sentence change so the user's manual
                // scroll-wheel use during playback isn't interrupted
                // by every word tick from the aligner.
                view.go(to: sentenceSelection)
            }
        }

        if subRangeChanged {
            removeSubAnnotations(coordinator: coordinator)
            coordinator.lastSubRange = spokenSubRange
            if let sentence = activeSentence,
               let sub = spokenSubRange,
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
                        coordinator.subAnnotations.append((annotation, page))
                    }
                }
            }
        }
    }

    private func removeSentenceAnnotations(coordinator: Coordinator) {
        for (annotation, page) in coordinator.sentenceAnnotations {
            page.removeAnnotation(annotation)
        }
        coordinator.sentenceAnnotations = []
    }

    private func removeSubAnnotations(coordinator: Coordinator) {
        for (annotation, page) in coordinator.subAnnotations {
            page.removeAnnotation(annotation)
        }
        coordinator.subAnnotations = []
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
        removeSentenceAnnotations(coordinator: coordinator)
        removeSubAnnotations(coordinator: coordinator)
        coordinator.lastSentenceKey = nil
        coordinator.lastSubRange = nil
    }

    fileprivate struct SentenceKey: Equatable {
        let blockIndex: Int
        let offsetInBlock: Int
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
        /// Split into sentence-level and sub-level so a word tick
        /// only rebuilds the (usually 1-line) sub-highlight — the
        /// multi-line sentence wash stays cached until the sentence
        /// itself changes. Previously every word tick tore down and
        /// rebuilt both, which for a multi-line sentence meant 3–6
        /// PDFAnnotation removals + creations per tick.
        var sentenceAnnotations: [(PDFAnnotation, PDFPage)] = []
        var subAnnotations: [(PDFAnnotation, PDFPage)] = []
        var lastSentenceKey: SentenceKey?
        var lastSubRange: NSRange?
    }
}

// MARK: - Click-to-start for PDF

/// `PDFView` subclass that turns a double-click or right-click's
/// "Read from here" into a (page, page-offset) callback. Character
/// offsets are recovered via `PDFPage.characterIndex(at:)`, which
/// speaks *page-space* coordinates and UTF-16 offsets into
/// `page.string` — the same coordinate system the extractor's
/// `DocumentBlock.offsetInPage` and `Sentence.offsetInBlock` live in,
/// so the host can look up the sentence without any translation.
private final class ClickablePDFView: PDFView {
    var onReadFromLocation: ((PDFClickLocation) -> Void)?

    private var pendingMenuLocation: PDFClickLocation?

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard event.clickCount == 2 else { return }
        guard let location = pdfLocation(for: event) else { return }
        onReadFromLocation?(location)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard let location = pdfLocation(for: event) else { return menu }
        pendingMenuLocation = location

        let readHere = NSMenuItem(
            title: "Read from here",
            action: #selector(readFromHere(_:)),
            keyEquivalent: ""
        )
        readHere.target = self
        let readToEnd = NSMenuItem(
            title: "Read from here to end",
            action: #selector(readFromHere(_:)),
            keyEquivalent: ""
        )
        readToEnd.target = self
        // The two items resolve to the same action today — playback
        // naturally ends at the sentence queue's tail — but we still
        // expose them as two menu items so users who expect the
        // Speechify-style "to end" affordance find it where they
        // look. If we ever add auto-stop bookmarks, the two paths
        // will diverge at that point.

        if menu.items.isEmpty {
            menu.addItem(readHere)
            menu.addItem(readToEnd)
        } else {
            menu.insertItem(.separator(), at: 0)
            menu.insertItem(readToEnd, at: 0)
            menu.insertItem(readHere, at: 0)
        }
        return menu
    }

    @objc private func readFromHere(_ sender: Any?) {
        guard let location = pendingMenuLocation else { return }
        pendingMenuLocation = nil
        onReadFromLocation?(location)
    }

    private func pdfLocation(for event: NSEvent) -> PDFClickLocation? {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = self.page(for: viewPoint, nearest: true),
              let document = document else { return nil }
        let pagePoint = convert(viewPoint, to: page)
        let charIdx = page.characterIndex(at: pagePoint)
        guard charIdx >= 0 else { return nil }
        let pageIndex = document.index(for: page)
        return PDFClickLocation(pageIndex: pageIndex, pageOffset: charIdx)
    }
}
