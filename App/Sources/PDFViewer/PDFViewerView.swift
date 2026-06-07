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
    @State private var search = SearchState()
    @State private var searchSelections: [PDFSelection] = []
    @State private var followState = ReaderFollowState()

    var body: some View {
        Group {
            switch loadResult {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.readAloudTTSAccent)
            case .loaded(let document):
                ZStack(alignment: .topTrailing) {
                    PDFViewRepresentable(
                        document: document,
                        blocks: blocks,
                        activeSentence: activeSentence,
                        spokenSubRange: player.spokenSubRange,
                        searchSelections: searchSelections,
                        currentSearchIndex: search.currentIndex,
                        followState: followState,
                        onReadFromLocation: handleReadFromLocation
                    )
                    .overlay(alignment: .bottomLeading) { statusFooter(pageCount: document.pageCount) }
                    .overlay(alignment: .bottom) {
                        JumpToCurrentButton(followState: followState, player: player)
                    }

                    if search.isPresented {
                        SearchBar(
                            state: search,
                            onSubmit: { runSearch(in: document) },
                            onNext: { advanceMatch(by: 1) },
                            onPrev: { advanceMatch(by: -1) },
                            onDismiss: dismissSearch
                        )
                        .padding(.top, 8)
                        .padding(.trailing, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .task(id: url) {
                    let extracted = await PDFTextExtractor.extract(
                        document,
                        skipFigureCaptions: SpeechSettings.shared.skipFigureCaptions
                    )
                    blocks = extracted
                    let parsed = await SentenceSegmenter.segment(extracted, reflowLineWraps: true)
                    sentences = parsed
                    player.load(parsed)
                }
            case .failed:
                errorState
            }
        }
        .task(id: url) {
            followState.resumeFollowing()
            loadResult = .loading
            blocks = []
            sentences = []
            if let document = await PDFDocumentLoader.load(url: url) {
                loadResult = .loaded(document)
            } else {
                loadResult = .failed
            }
        }
        .onChange(of: player.state.isPlaying) { wasPlaying, isPlaying in
            if !wasPlaying, isPlaying { followState.jumpToCurrent() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppScene.findNotification)) { _ in
            presentSearch()
        }
    }

    // MARK: - Search

    private func presentSearch() {
        if !search.isPresented {
            withAnimation(.easeOut(duration: 0.15)) {
                search.isPresented = true
            }
        }
        if case .loaded(let document) = loadResult {
            runSearch(in: document)
        }
    }

    private func dismissSearch() {
        withAnimation(.easeOut(duration: 0.15)) {
            search.isPresented = false
        }
        searchSelections = []
        search.totalMatches = 0
        search.currentIndex = -1
    }

    /// Resolves the current query against the PDF. Plain queries route
    /// through PDFKit's native findString (case-insensitive when the
    /// toggle is off). Regex falls back to a per-page scan because
    /// PDFKit doesn't expose a regex API; we walk each `page.string`
    /// with NSRegularExpression and translate the matches into
    /// `PDFSelection`s via `page.selection(for: NSRange)`.
    private func runSearch(in document: PDFDocument) {
        let query = search.query
        guard !query.isEmpty else {
            searchSelections = []
            search.totalMatches = 0
            search.currentIndex = -1
            return
        }

        var selections: [PDFSelection] = []
        if search.useRegex {
            var options: NSRegularExpression.Options = []
            if !search.caseSensitive { options.insert(.caseInsensitive) }
            guard let regex = try? NSRegularExpression(pattern: query, options: options) else {
                searchSelections = []
                search.totalMatches = 0
                search.currentIndex = -1
                return
            }
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex),
                      let pageString = page.string else { continue }
                let nsString = pageString as NSString
                let full = NSRange(location: 0, length: nsString.length)
                for match in regex.matches(in: pageString, options: [], range: full) {
                    guard match.range.length > 0,
                          let selection = page.selection(for: match.range) else {
                        continue
                    }
                    selections.append(selection)
                }
            }
        } else {
            var options: NSString.CompareOptions = []
            if !search.caseSensitive { options.insert(.caseInsensitive) }
            selections = document.findString(query, withOptions: options)
        }

        searchSelections = selections
        search.totalMatches = selections.count
        if selections.isEmpty {
            search.currentIndex = -1
        } else if search.currentIndex < 0 || search.currentIndex >= selections.count {
            search.currentIndex = 0
        }
    }

    private func advanceMatch(by delta: Int) {
        guard !searchSelections.isEmpty else { return }
        let next = (search.currentIndex + delta + searchSelections.count) % searchSelections.count
        search.currentIndex = next
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
        followState.jumpToCurrent()
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
                .foregroundStyle(Color.readAloudTTSAccent)
            Text("Couldn't open \(url.lastPathComponent).")
                .font(ReadAloudTTSFont.serif(18))
                .foregroundStyle(.primary)
            Text("Drop another file to try again.")
                .font(ReadAloudTTSFont.ui(13))
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
    let searchSelections: [PDFSelection]
    let currentSearchIndex: Int
    let followState: ReaderFollowState
    let onReadFromLocation: (PDFClickLocation) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = ClickablePDFView()
        view.onReadFromLocation = onReadFromLocation
        view.onUserScroll = { [followState] in followState.userDidScroll() }
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = NSColor(Color.readAloudTTSSurface)
        view.autoScales = true
        view.document = document
        view.unregisterDraggedTypes()
        // `autoScales` is evaluated once against current bounds when
        // the document is assigned. In a split view the detail column
        // often has 0-width at makeNSView time, so PDFKit picks a
        // fit-scale that leaves the page clipped when the view
        // finally resizes. `needsInitialFit` lets the subclass re-run
        // the fit once real bounds arrive.
        view.needsInitialFit = true
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if let clickable = nsView as? ClickablePDFView {
            clickable.onReadFromLocation = onReadFromLocation
            clickable.onUserScroll = { [followState] in followState.userDidScroll() }
        }
        if nsView.document !== document {
            removeHighlight(coordinator: context.coordinator)
            nsView.document = document
            if let clickable = nsView as? ClickablePDFView {
                clickable.needsInitialFit = true
            }
        }
        applyHighlight(view: nsView, coordinator: context.coordinator)
        applySearchSelections(view: nsView, coordinator: context.coordinator)
        handleJumpRequest(view: nsView, coordinator: context.coordinator)
    }

    /// Scroll back to the current sentence when the user taps "jump to
    /// current". Bridged from SwiftUI via `followState.jumpToken`.
    private func handleJumpRequest(view: PDFView, coordinator: Coordinator) {
        guard coordinator.lastHandledJumpToken != followState.jumpToken else { return }
        coordinator.lastHandledJumpToken = followState.jumpToken
        guard let sentence = activeSentence,
              let selection = selection(for: sentence) else { return }
        view.go(to: selection)
    }

    /// Drives PDFView's native match highlight + scroll. Updates the
    /// yellow `highlightedSelections` bag whenever the match set
    /// changes, then issues `setCurrentSelection` only when the active
    /// match changes — `setCurrentSelection` triggers a scroll, so we
    /// guard against re-issuing for the same selection on every state
    /// tick.
    private func applySearchSelections(view: PDFView, coordinator: Coordinator) {
        let selectionIDs = searchSelections.map(ObjectIdentifier.init)
        if coordinator.lastSearchSelectionIDs != selectionIDs {
            view.highlightedSelections = searchSelections.isEmpty ? nil : searchSelections
            coordinator.lastSearchSelectionIDs = selectionIDs
        }
        let active: PDFSelection?
        if currentSearchIndex >= 0, currentSearchIndex < searchSelections.count {
            active = searchSelections[currentSearchIndex]
        } else {
            active = nil
        }
        let activeID = active.map(ObjectIdentifier.init)
        if coordinator.lastCurrentSearchID != activeID {
            coordinator.lastCurrentSearchID = activeID
            if let active {
                view.setCurrentSelection(active, animate: false)
                view.scrollSelectionToVisible(nil)
            } else {
                view.setCurrentSelection(nil, animate: false)
            }
        }
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
                let soft = HighlightStyle.current.sentenceBand
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
                // scroll-wheel use during playback isn't interrupted by
                // every word tick from the aligner — and only while
                // following, so a deliberate scroll-away stays put until
                // the user taps "jump to current".
                if followState.isFollowing {
                    view.go(to: sentenceSelection)
                }
            }
        }

        if subRangeChanged {
            removeSubAnnotations(coordinator: coordinator)
            coordinator.lastSubRange = spokenSubRange
            if let sentence = activeSentence,
               let sub = spokenSubRange,
               let wordSelection = wordSelection(for: sentence, subRange: sub) {
                let bright = HighlightStyle.current.activeWord
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
        /// PDFSelection identity bag used to decide when to re-publish
        /// `highlightedSelections`. PDFSelection isn't Hashable, so we
        /// stash ObjectIdentifiers — same instance means PDFKit has
        /// already mounted the highlight.
        var lastSearchSelectionIDs: [ObjectIdentifier] = []
        var lastCurrentSearchID: ObjectIdentifier?
        var lastHandledJumpToken = 0
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
    /// Fired when the user scrolls or pans the document by hand (not a
    /// programmatic `go(to:)`), so the reader can drop out of follow
    /// mode. Keyboard scrolling is not detected — a known v1 gap.
    var onUserScroll: (() -> Void)?
    /// Set by the host when a document is (re)assigned so the next
    /// valid layout pass forces a refit. Separate from the zoom-lock
    /// below because loading a new document always wants to reset the
    /// fit, even if the user had zoomed in on the previous one.
    var needsInitialFit: Bool = false

    /// Turned on by explicit user zoom (⌘+wheel) and cleared by
    /// `restoreDefaultLook()`. While off, every width change re-runs
    /// the fit-to-width computation; this is the piece that keeps the
    /// page aligned after the NavigationSplitView sidebar animates in.
    private var userControlsZoom = false

    private var pendingMenuLocation: PDFClickLocation?
    private var panAnchorWindowPoint: NSPoint?
    private var panStartClipOrigin: NSPoint = .zero
    private var pushedPanCursor = false
    private var lastFitWidth: CGFloat = 0
    private var scrollMonitor: Any?
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var notificationObservers: [NSObjectProtocol] = []
    private static let zoomStep: CGFloat = 1.08
    private static let minZoomMultiplier: CGFloat = 0.25
    private static let maxZoomMultiplier: CGFloat = 6.0

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeEventMonitors()
        } else {
            installEventMonitors()
        }
    }

    deinit {
        removeEventMonitors()
    }

    // Window-level NSEvent monitors. PDFView wraps an internal
    // NSScrollView that consumes `scrollWheel`, `otherMouseDown`,
    // and key events before they can bubble to this subclass, so
    // method overrides on `ClickablePDFView` never fire. Local
    // monitors run inside the app's event loop before the view
    // hierarchy sees the event, letting us intercept ⌘+wheel zoom,
    // middle-button pan, and Escape while leaving normal scroll /
    // click behavior untouched.
    private func installEventMonitors() {
        removeEventMonitors()
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
            [weak self] event in
            guard let self else { return event }
            return self.handleScroll(event)
        }
        let mouseMask: NSEvent.EventTypeMask = [
            .otherMouseDown, .otherMouseDragged, .otherMouseUp
        ]
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseMask) {
            [weak self] event in
            guard let self else { return event }
            return self.handleMouse(event)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }

        // Keyboard ⌘+ / ⌘- / ⌘0 zoom. The View menu posts these
        // notifications for the non-PDF readers (where they drive
        // ReaderSettings.fontScale) — we also adopt them here so the
        // same shortcut zooms the visible PDF. ReaderSettings still
        // ticks in the background, but it's only consulted by the
        // markdown/EPUB/text readers, so there's no cross-contamination.
        let center = NotificationCenter.default
        let queue = OperationQueue.main
        notificationObservers.append(
            center.addObserver(
                forName: AppScene.increaseFontNotification,
                object: nil, queue: queue
            ) { [weak self] _ in self?.zoomFromKeyboard(factor: Self.zoomStep) }
        )
        notificationObservers.append(
            center.addObserver(
                forName: AppScene.decreaseFontNotification,
                object: nil, queue: queue
            ) { [weak self] _ in self?.zoomFromKeyboard(factor: 1.0 / Self.zoomStep) }
        )
        notificationObservers.append(
            center.addObserver(
                forName: AppScene.resetFontNotification,
                object: nil, queue: queue
            ) { [weak self] _ in self?.restoreDefaultLook() }
        )
    }

    private func removeEventMonitors() {
        if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil }
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        for token in notificationObservers {
            NotificationCenter.default.removeObserver(token)
        }
        notificationObservers.removeAll()
    }

    /// Keyboard-driven zoom. Pins the cursor anchor to the view's
    /// center because there's no mouse position when the shortcut
    /// fires; behaves like Preview.app's ⌘+ / ⌘-.
    private func zoomFromKeyboard(factor: CGFloat) {
        let anchor = NSPoint(x: bounds.midX, y: bounds.midY)
        zoom(by: factor, around: anchor)
    }

    private func eventIsOverMe(_ event: NSEvent) -> Bool {
        guard event.window === self.window, self.window != nil else { return false }
        let viewPoint = convert(event.locationInWindow, from: nil)
        return bounds.contains(viewPoint)
    }

    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        // A plain scroll over the document is the user taking manual
        // control — let the reader stop following the highlight. Cmd+
        // scroll is zoom, not a scroll, so it doesn't count.
        if !event.modifierFlags.contains(.command), eventIsOverMe(event) {
            onUserScroll?()
        }
        guard event.modifierFlags.contains(.command), eventIsOverMe(event) else {
            return event
        }
        let delta = event.scrollingDeltaY != 0
            ? event.scrollingDeltaY
            : event.deltaY
        guard abs(delta) > 0.01 else { return nil }
        let factor: CGFloat = delta > 0
            ? Self.zoomStep
            : 1.0 / Self.zoomStep
        let viewPoint = convert(event.locationInWindow, from: nil)
        zoom(by: factor, around: viewPoint)
        return nil  // consume so PDFView doesn't also scroll
    }

    private func handleMouse(_ event: NSEvent) -> NSEvent? {
        // buttonNumber == 2 is the middle button; Logitech / MX
        // Master wheel-click maps here.
        guard event.buttonNumber == 2 else { return event }
        switch event.type {
        case .otherMouseDown:
            guard eventIsOverMe(event) else { return event }
            window?.makeFirstResponder(self)
            panAnchorWindowPoint = event.locationInWindow
            panStartClipOrigin = enclosingClipView?.bounds.origin ?? .zero
            if !pushedPanCursor {
                NSCursor.closedHand.push()
                pushedPanCursor = true
            }
            return nil
        case .otherMouseDragged:
            guard let anchor = panAnchorWindowPoint,
                  let clipView = enclosingClipView else { return event }
            onUserScroll?()
            let current = event.locationInWindow
            let dx = anchor.x - current.x
            // Clip view origin moves +y to scroll the document *down*
            // when flipped; window y increases upward, so invert when
            // the clip isn't flipped.
            let dy = clipView.isFlipped
                ? current.y - anchor.y
                : anchor.y - current.y
            var origin = panStartClipOrigin
            origin.x += dx
            origin.y += dy
            clipView.scroll(to: origin)
            clipView.enclosingScrollView?.reflectScrolledClipView(clipView)
            return nil
        case .otherMouseUp:
            if panAnchorWindowPoint != nil {
                endPan()
                return nil
            }
            return event
        default:
            return event
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        // keyCode 53 is Escape. Only consume when the PDFView (or
        // one of its descendants) is first responder, so Esc on the
        // sidebar or transport still does whatever else it did.
        guard event.keyCode == 53, isFirstResponderSelfOrDescendant() else {
            return event
        }
        restoreDefaultLook()
        return nil
    }

    private func isFirstResponderSelfOrDescendant() -> Bool {
        guard let responder = window?.firstResponder as? NSView else {
            return false
        }
        var cursor: NSView? = responder
        while let current = cursor {
            if current === self { return true }
            cursor = current.superview
        }
        return false
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // SwiftUI sets the frame directly rather than marking the
        // view dirty, so `layout()` isn't reliably called. Drive the
        // fit-to-width recomputation off every real width change,
        // because `autoScales` frequently misses the post-init width
        // shrink when the NavigationSplitView sidebar animates in.
        guard newSize.width > 1,
              newSize.height > 1,
              document != nil,
              !userControlsZoom else { return }
        needsInitialFit = false
        // Deferred so PDFKit finishes the in-flight frame propagation
        // before we read `scaleFactorForSizeToFit`; reading it too
        // early returns the old fit scale against the old bounds.
        DispatchQueue.main.async { [weak self] in
            self?.applyFitToWidth()
        }
    }

    private func applyFitToWidth() {
        guard !userControlsZoom, document != nil else { return }
        let fit = scaleFactorForSizeToFit
        guard fit > 0 else { return }
        // `autoScales` has to be off before manually setting
        // `scaleFactor`; otherwise PDFKit ignores the assignment.
        autoScales = false
        scaleFactor = fit
        lastFitWidth = bounds.width
    }

    override func mouseDown(with event: NSEvent) {
        // Claim first responder so Escape / key-based shortcuts reach
        // `keyDown(with:)`. PDFView doesn't always promote itself on
        // click when hosted inside SwiftUI.
        window?.makeFirstResponder(self)
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

    // MARK: - Zoom, pan, restore

    private func endPan() {
        panAnchorWindowPoint = nil
        if pushedPanCursor {
            NSCursor.pop()
            pushedPanCursor = false
        }
    }

    private var enclosingClipView: NSClipView? {
        // PDFView wraps its document in a private scroll view; walk
        // the subview tree to find the clip view we can scroll.
        func find(in view: NSView) -> NSClipView? {
            if let scroll = view as? NSScrollView { return scroll.contentView }
            for sub in view.subviews {
                if let clip = find(in: sub) { return clip }
            }
            return nil
        }
        return find(in: self)
    }

    private func zoom(by factor: CGFloat, around viewPoint: NSPoint) {
        let fitScale = scaleFactorForSizeToFit
        guard fitScale > 0 else { return }
        let minScale = fitScale * Self.minZoomMultiplier
        let maxScale = fitScale * Self.maxZoomMultiplier
        let oldScale = scaleFactor
        let newScale = max(minScale, min(maxScale, oldScale * factor))
        guard abs(newScale - oldScale) > 0.0001 else { return }

        guard let clipView = enclosingClipView else {
            userControlsZoom = true
            autoScales = false
            scaleFactor = newScale
            return
        }

        // Canonical "zoom-around-cursor" affine used by Figma,
        // Photoshop, Google Maps, etc. In a single step:
        //
        //     newOffset = cursor − (cursor − oldOffset) × (newScale / oldScale)
        //
        // `cursor` and `offset` are both in the document view's
        // coord system (the clip view's bounds is expressed in that
        // system too). Derived from the invariant "the document
        // point under the cursor before the zoom is the document
        // point under the cursor after the zoom":
        //
        //     (cursor − oldOffset) / oldScale == (cursor − newOffset) / newScale
        //
        // Solving for newOffset gives the formula above. Working in
        // one step avoids a pdfkit race where `scaleFactor` and
        // `scroll(to:)` applied separately can interleave.
        let cursorInClip = clipView.convert(viewPoint, from: self)
        let cursorInDoc = NSPoint(
            x: clipView.bounds.origin.x + cursorInClip.x,
            y: clipView.bounds.origin.y + cursorInClip.y
        )
        let scaleRatio = newScale / oldScale
        // Textbook "zoom-around-cursor" form (Figma / PureRef /
        // Photoshop / Google Maps all do this). The post-zoom clip
        // origin must satisfy:
        //
        //     cursorInDoc × scaleRatio − newOffset == cursorInClip
        //
        // which keeps the viewport-local cursor pixel pointing at
        // the same document content after the scale change.
        let anchoredOffset = NSPoint(
            x: cursorInDoc.x * scaleRatio - cursorInClip.x,
            y: cursorInDoc.y * scaleRatio - cursorInClip.y
        )

        userControlsZoom = true
        autoScales = false
        // Apply scale and offset atomically to avoid the PDFKit
        // race. `setBoundsOrigin` is synchronous (no animation),
        // which `scroll(to:)` would otherwise wrap in an implicit
        // CA animation and cause a one-frame drift.
        scaleFactor = newScale
        clipView.setBoundsOrigin(anchoredOffset)
        clipView.enclosingScrollView?.reflectScrolledClipView(clipView)
    }

    private func restoreDefaultLook() {
        // Remember the page the user is currently looking at, so we
        // can keep their reading position after the zoom reset.
        let anchorPoint = convert(
            NSPoint(x: bounds.midX, y: bounds.midY),
            from: nil
        )
        let anchorPage = page(for: anchorPoint, nearest: true)

        userControlsZoom = false
        applyFitToWidth()

        // Reset horizontal pan to 0 and keep the vertical position
        // aligned to the anchor page the user was reading. Skipping
        // this would leave the user's current paragraph off-screen
        // after a deep zoom-out.
        if let anchorPage {
            go(to: anchorPage)
        }
        if let clipView = enclosingClipView {
            var origin = clipView.bounds.origin
            origin.x = 0
            clipView.scroll(to: origin)
            clipView.enclosingScrollView?.reflectScrolledClipView(clipView)
        }
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

