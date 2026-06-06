import SwiftUI
import AppKit
import WebKit
import os

/// The Markdown reader. Two view modes:
/// - **Preview** (default): Foundation parses the markdown into an
///   `AttributedString`; we walk the runs to translate
///   `inlinePresentationIntent` / `presentationIntent` into NSFont /
///   NSColor visual styling and *insert explicit `\n\n` separators
///   between distinct block identities*, because the Foundation
///   parser does not include block-boundary newlines in the
///   character stream.
/// - **Source**: raw markdown text in monospace, useful for
///   inspecting syntax. Highlight only renders in Preview because
///   the player's sentence offsets are computed against the rendered
///   plain text.
///
/// Sentence segmentation always runs against the rendered plain
/// text so the existing offset-based highlight path lights up the
/// correct range in the displayed `NSTextStorage`.
struct MarkdownReaderView: View {
    let url: URL
    let player: SpeechPlayer

    @State private var rawSource: String = ""
    @State private var rendered: NSAttributedString = .init()
    @State private var sentences: [Sentence] = []
    @State private var loadFailed = false
    @State private var viewMode: ViewMode = .preview
    @State private var search = SearchState()
    @State private var searchMatches: [NSRange] = []
    /// Source the preview was last rendered from. Lets us re-render
    /// only when the editor's buffer actually drifts past what's on
    /// screen instead of on every mode switch.
    @State private var lastRenderedSource: String?

    /// Cache of resolved Mermaid diagrams keyed by raw source. The
    /// renderer reads this when emitting attachments so cached images
    /// appear inline immediately on subsequent re-renders.
    @State private var mermaidImages: [String: NSImage] = [:]
    /// Sources we're currently rendering off-thread. Prevents kicking
    /// off duplicate WKWebView renders for the same diagram.
    @State private var inflightMermaid: Set<String> = []
    /// Cache of resolved `![alt](url)` images keyed by their resolved
    /// URL. Loaded asynchronously after the first render so a wide
    /// column never blocks on disk I/O.
    @State private var markdownImages: [URL: NSImage] = [:]
    @State private var inflightImageURLs: Set<URL> = []
    /// Session-only per-figure width store. Survives re-renders
    /// (font scale change, mermaid/image resolve) so the user's resize
    /// gestures aren't clobbered. Held in `@State` as a reference type
    /// so width writes don't trigger SwiftUI updates.
    @State private var figureWidths = FigureWidthCache()

    @Bindable private var store = MarkdownDocumentStore.shared
    @Bindable private var readerSettings = ReaderSettings.shared

    enum ViewMode: String, CaseIterable, Identifiable {
        case preview = "Preview"
        case source = "Source"
        var id: Self { self }
    }

    private static let log = Logger(subsystem: "app.readaloudtts.mac", category: "markdown")

    var body: some View {
        VStack(spacing: 0) {
            modeBar
            Divider()

            ZStack(alignment: .topTrailing) {
                Group {
                    if loadFailed {
                        errorState
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        switch viewMode {
                        case .preview:
                            MarkdownTextView(
                                attributed: rendered,
                                activeSentence: activeSentence,
                                spokenSubRange: player.spokenSubRange,
                                searchMatches: searchMatches,
                                currentMatchIndex: search.currentIndex,
                                readingTheme: readerSettings.readingTheme,
                                onReadFromOffset: handleReadFromOffset
                            )
                        case .source:
                            EditableSourceTextView(
                                url: url,
                                searchMatches: searchMatches,
                                currentMatchIndex: search.currentIndex,
                                fontScale: readerSettings.fontScale
                            )
                        }
                    }
                }

                if search.isPresented {
                    SearchBar(
                        state: search,
                        onSubmit: runSearch,
                        onNext: { advanceMatch(by: 1) },
                        onPrev: { advanceMatch(by: -1) },
                        onDismiss: dismissSearch
                    )
                    .padding(.top, 8)
                    .padding(.trailing, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .task(id: url) {
            await load()
        }
        .onChange(of: viewMode) { _, newMode in
            if newMode == .preview { refreshPreviewIfNeeded() }
        }
        .onChange(of: store.documents[url.standardizedFileURL.path]?.currentText) { _, _ in
            // The editor or an external save changed the buffer. Re-run
            // the active search so highlight ranges track edits.
            if search.isPresented { runSearch() }
        }
        .onChange(of: readerSettings.fontScale) { _, _ in
            // User adjusted ⌘+ / ⌘- (or moved the header slider): re-
            // render the preview with the fresh scale. Sentence offsets
            // are character-position based, so playback alignment
            // survives the resize.
            rerenderAttributedFromCache()
        }
        .onChange(of: ReaderTypography(from: readerSettings)) { _, _ in
            // Body face, line height, or letter spacing changed in the
            // Reading settings tab. Re-render the attributed string only;
            // character content is identical so cached sentence offsets
            // and playback alignment stay valid.
            rerenderAttributedFromCache()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppScene.findNotification)) { _ in
            presentSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppScene.saveNotification)) { _ in
            saveCurrent()
        }
    }

    private var modeBar: some View {
        HStack {
            Picker("", selection: $viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)

            if isDirty {
                Text("Edited")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.secondary.opacity(0.12))
                    )
            }

            Spacer()

            FontSizeControl()

            Button {
                presentSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Find in document (\u{2318}F)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var isDirty: Bool { store.isDirty(url: url) }

    private var activeSentence: Sentence? {
        guard let index = player.state.sentenceIndex,
              index >= 0, index < sentences.count else { return nil }
        return sentences[index]
    }

    private func handleReadFromOffset(_ offset: Int) {
        guard let idx = ReaderHitTester.sentenceIndex(
            forOffset: offset, in: sentences
        ) else { return }
        player.playFromSentence(idx)
    }

    private func load() async {
        let started = ContinuousClock.now
        do {
            let raw = try String(contentsOf: url, encoding: .utf8)
            // Register with the store before rendering so the editor's
            // first read of `currentText` already reflects the on-disk
            // baseline (or a preserved dirty buffer from a previous
            // open of the same file).
            store.register(url: url, contents: raw)
            let buffer = store.currentText(url: url) ?? raw
            rawSource = buffer
            Self.log.info("read \(raw.count) chars")

            await renderAndSegment(from: buffer, started: started)
            loadFailed = false
        } catch {
            Self.log.error("failed to read \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            rawSource = ""
            rendered = NSAttributedString()
            sentences = []
            loadFailed = true
            player.load([])
        }
    }

    /// Render the preview from the supplied source text and refresh
    /// the sentence queue. Pulled out of `load()` so re-renders after
    /// edits don't have to re-read the file from disk.
    private func renderAndSegment(from buffer: String, started: ContinuousClock.Instant) async {
        let parseStart = ContinuousClock.now
        let attributed = MarkdownRenderer.render(
            buffer,
            mermaidImages: mermaidImages,
            markdownImages: markdownImages,
            widthCache: figureWidths,
            fontScale: readerSettings.fontScale,
            typography: ReaderTypography(from: readerSettings),
            baseURL: url.deletingLastPathComponent()
        )
        Self.log.info("rendered markdown in \(ContinuousClock.now - parseStart, privacy: .public)")

        rendered = attributed
        lastRenderedSource = buffer

        let segmentStart = ContinuousClock.now
        let plain = attributed.string
        let block = DocumentBlock(text: plain, pageIndex: 0, offsetInPage: 0)
        let parsed = await SentenceSegmenter.segment([block])
        let merged = Self.coalesceTableRows(parsed, in: attributed)
        Self.log.info("segmented \(parsed.count) → \(merged.count) sentences in \(ContinuousClock.now - segmentStart, privacy: .public)")

        sentences = merged
        player.load(merged)

        Self.log.info("TOTAL md load \(ContinuousClock.now - started, privacy: .public)")

        kickOffMermaidRenders(in: attributed)
        kickOffImageLoads(in: attributed)
    }

    /// Walks the rendered string for Mermaid placeholders and starts a
    /// WKWebView render for any source we haven't already cached or
    /// dispatched. When each render resolves we update the cache and
    /// re-render `attributed` only — sentences/playback offsets stay
    /// stable because the attachment occupies a single `\u{FFFC}` code
    /// point regardless of whether it shows the placeholder or the
    /// final diagram.
    private func kickOffMermaidRenders(in attributed: NSAttributedString) {
        let sources = Self.uniqueMermaidSources(in: attributed)
        for source in sources where mermaidImages[source] == nil
                                  && !inflightMermaid.contains(source) {
            inflightMermaid.insert(source)
            Task { @MainActor in
                defer { inflightMermaid.remove(source) }
                do {
                    let image = try await MermaidWebRenderer.shared.render(source: source)
                    mermaidImages[source] = image
                    rerenderAttributedFromCache()
                } catch {
                    Self.log.error("mermaid render failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    /// Re-renders the attributed string against `lastRenderedSource`
    /// so newly-resolved Mermaid images replace placeholders. We
    /// deliberately skip `SentenceSegmenter` here — character content
    /// is byte-identical to the placeholder version, so the cached
    /// `sentences` array is still valid.
    private func rerenderAttributedFromCache() {
        guard let buffer = lastRenderedSource else { return }
        rendered = MarkdownRenderer.render(
            buffer,
            mermaidImages: mermaidImages,
            markdownImages: markdownImages,
            widthCache: figureWidths,
            fontScale: readerSettings.fontScale,
            typography: ReaderTypography(from: readerSettings),
            baseURL: url.deletingLastPathComponent()
        )
    }

    /// Walks the rendered string for markdown image placeholders and
    /// loads the underlying file/URL into `markdownImages` if we haven't
    /// already. On resolution we re-render so the placeholder swaps for
    /// the real image and the attachment picks up its true aspect ratio.
    private func kickOffImageLoads(in attributed: NSAttributedString) {
        let urls = Self.uniqueMarkdownImageURLs(in: attributed)
        for imageURL in urls where markdownImages[imageURL] == nil
                                && !inflightImageURLs.contains(imageURL) {
            inflightImageURLs.insert(imageURL)
            Task { @MainActor in
                defer { inflightImageURLs.remove(imageURL) }
                if let image = await Self.loadMarkdownImage(at: imageURL) {
                    markdownImages[imageURL] = image
                    rerenderAttributedFromCache()
                }
            }
        }
    }

    /// File URLs decode synchronously off the main thread; remote URLs
    /// fetch via the shared `URLSession`. Returns `nil` on any failure
    /// so the renderer keeps showing the placeholder rather than
    /// flashing a missing-image glyph.
    private static func loadMarkdownImage(at url: URL) async -> NSImage? {
        if url.isFileURL {
            return await Task.detached(priority: .utility) {
                return NSImage(contentsOf: url)
            }.value
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return NSImage(data: data)
        } catch {
            return nil
        }
    }

    private static func uniqueMarkdownImageURLs(in attributed: NSAttributedString) -> Set<URL> {
        var urls = Set<URL>()
        let full = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.readAloudTTSMarkdownImageURL, in: full, options: []) { value, _, _ in
            if let u = value as? URL { urls.insert(u) }
        }
        return urls
    }

    private static func uniqueMermaidSources(in attributed: NSAttributedString) -> Set<String> {
        var sources = Set<String>()
        let full = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.readAloudTTSMermaidSource, in: full, options: []) { value, _, _ in
            if let s = value as? String { sources.insert(s) }
        }
        return sources
    }

    /// Re-render the preview from the editor's latest buffer when the
    /// user flips back from Source. Skipping when the buffer hasn't
    /// changed avoids re-segmenting — playback offsets stay valid.
    private func refreshPreviewIfNeeded() {
        let latest = store.currentText(url: url) ?? rawSource
        guard latest != lastRenderedSource else { return }
        rawSource = latest
        Task { @MainActor in
            await renderAndSegment(from: latest, started: ContinuousClock.now)
            if search.isPresented { runSearch() }
        }
    }

    // MARK: - Save

    private func saveCurrent() {
        guard isDirty else { return }
        let success = store.save(url: url)
        if !success {
            Self.log.error("failed to save \(url.lastPathComponent, privacy: .public)")
            NSSound.beep()
        }
    }

    // MARK: - Search

    private func presentSearch() {
        if !search.isPresented {
            withAnimation(.easeOut(duration: 0.15)) {
                search.isPresented = true
            }
        }
        runSearch()
    }

    private func dismissSearch() {
        withAnimation(.easeOut(duration: 0.15)) {
            search.isPresented = false
        }
        searchMatches = []
        search.totalMatches = 0
        search.currentIndex = -1
    }

    private func runSearch() {
        let haystack: String
        switch viewMode {
        case .preview:
            haystack = rendered.string
        case .source:
            haystack = store.currentText(url: url) ?? rawSource
        }
        let matches = TextSearcher.search(in: haystack, options: search)
        searchMatches = matches
        search.totalMatches = matches.count
        if matches.isEmpty {
            search.currentIndex = -1
        } else if search.currentIndex < 0 || search.currentIndex >= matches.count {
            search.currentIndex = 0
        }
    }

    private func advanceMatch(by delta: Int) {
        guard !searchMatches.isEmpty else { return }
        let next = (search.currentIndex + delta + searchMatches.count) % searchMatches.count
        search.currentIndex = next
    }

    /// Collapse sentences that fall inside the same rendered table row
    /// into a single sentence. The renderer tags every character in a
    /// row with `.readAloudTTSTableRowID`; we walk the segmentation output,
    /// and any adjacent sentences whose starting character shares a
    /// row id get merged into one. The merged sentence's range spans
    /// all the cells so highlighting covers the whole row, and its
    /// `text` joins cell contents with `. ` so the TTS engine gives
    /// each cell a natural phrase break.
    private static func coalesceTableRows(
        _ sentences: [Sentence],
        in rendered: NSAttributedString
    ) -> [Sentence] {
        guard rendered.length > 0, !sentences.isEmpty else { return sentences }
        var merged: [Sentence] = []
        var i = 0
        while i < sentences.count {
            let first = sentences[i]
            guard first.offsetInBlock < rendered.length,
                  let rowID = rendered.attribute(
                    .readAloudTTSTableRowID,
                    at: first.offsetInBlock,
                    effectiveRange: nil
                  ) as? String
            else {
                merged.append(first)
                i += 1
                continue
            }

            var last = first
            var texts = [first.text]
            var j = i + 1
            while j < sentences.count {
                let next = sentences[j]
                guard next.offsetInBlock < rendered.length,
                      let nextID = rendered.attribute(
                        .readAloudTTSTableRowID,
                        at: next.offsetInBlock,
                        effectiveRange: nil
                      ) as? String,
                      nextID == rowID
                else { break }
                texts.append(next.text)
                last = next
                j += 1
            }

            let span = (last.offsetInBlock + last.lengthInBlock) - first.offsetInBlock
            merged.append(Sentence(
                text: texts.joined(separator: ". "),
                blockIndex: first.blockIndex,
                offsetInBlock: first.offsetInBlock,
                lengthInBlock: span
            ))
            i = j
        }
        return merged
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.readAloudTTSAccent)
            Text("Couldn't read \(url.lastPathComponent).")
                .font(ReadAloudTTSFont.serif(18))
                .foregroundStyle(.primary)
            Text("Drop another file to try again.")
                .font(ReadAloudTTSFont.ui(13))
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}

// MARK: - Custom attribute keys

extension NSAttributedString.Key {
    /// Per-row identifier applied to every character inside a rendered
    /// table row. `MarkdownReaderView.coalesceTableRows` uses it to
    /// merge sentence-tokenized cells back into one row-level sentence
    /// so TTS reads tables left-to-right a row at a time.
    static let readAloudTTSTableRowID = NSAttributedString.Key("readAloudTTSTableRowID")

    /// Raw Mermaid source attached to each placeholder attachment. The
    /// reader view uses it to look up a freshly-rendered diagram in
    /// the image cache and to dispatch deferred renders for sources
    /// it hasn't seen yet.
    static let readAloudTTSMermaidSource = NSAttributedString.Key("readAloudTTSMermaidSource")

    /// Resolved URL of a markdown `![alt](url)` image attached to its
    /// `ResizableFigureAttachment`. The reader view enumerates these so
    /// it knows which images still need to be loaded asynchronously.
    static let readAloudTTSMarkdownImageURL = NSAttributedString.Key("readAloudTTSMarkdownImageURL")
}

// MARK: - Markdown rendering

/// Parses GFM-flavored markdown into an `NSAttributedString`. Walks
/// the parsed `AttributedString` runs and rebuilds an output stream
/// with:
/// - block-boundary separators (`\n\n`) inserted between distinct
///   `presentationIntent.identity` values, because the Foundation
///   parser doesn't emit them in the character stream itself;
/// - per-run font/color attributes derived from inline and block
///   presentation intents (bold, italic, code, headers H1–H6);
/// - GFM tables reconstructed as native `NSTextTable` layouts.
///   Foundation emits one run per cell with components
///   `[tableCell, tableHeaderRow|tableRow, table]`; the default
///   block-boundary logic would stack each cell on its own line.
///   We intercept table-bearing runs, group them into cells and rows
///   keyed by the table's presentation identity, and flush the table
///   as paragraphs whose `NSTextTableBlock` paragraph style places
///   them in the correct grid slot — with thin horizontal dividers
///   between rows (no vertical borders, matching our reading layout).
@MainActor
enum MarkdownRenderer {
    static func render(
        _ markdown: String,
        mermaidImages: [String: NSImage] = [:],
        markdownImages: [URL: NSImage] = [:],
        widthCache: FigureWidthCache? = nil,
        fontScale: Double = 1.0,
        typography: ReaderTypography = ReaderTypography(),
        baseURL: URL? = nil
    ) -> NSAttributedString {
        let theme = Theme(scale: fontScale, typography: typography)

        let attributed: AttributedString
        do {
            attributed = try AttributedString(
                markdown: markdown,
                options: .init(
                    interpretedSyntax: .full,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        } catch {
            return NSAttributedString(
                string: markdown,
                attributes: [.font: theme.body, .foregroundColor: NSColor.labelColor]
            )
        }

        let result = NSMutableAttributedString()
        var lastBlockKey: [Int]? = nil
        var pendingTable: TableAccumulator? = nil
        var pendingMermaid: (identity: Int, source: String)? = nil

        for run in attributed.runs {
            let runRange = run.range
            let runText = String(attributed[runRange].characters)
            guard !runText.isEmpty else { continue }

            // Mermaid code fences (```mermaid …```) are rendered as a
            // single inline NSTextAttachment instead of styled code so
            // diagrams show up alongside prose. We accumulate runs that
            // share a code-block identity and flush once when the block
            // ends, mirroring the table accumulator pattern below.
            if let info = mermaidCodeBlockInfo(from: run.presentationIntent) {
                if let pending = pendingMermaid, pending.identity != info.identity {
                    flushMermaid(
                        pending, into: result, theme: theme,
                        images: mermaidImages, widthCache: widthCache
                    )
                    pendingMermaid = nil
                }
                if pendingMermaid == nil {
                    if let existing = pendingTable {
                        flushTable(existing, into: result, theme: theme)
                        pendingTable = nil
                    }
                    pendingMermaid = (info.identity, runText)
                    lastBlockKey = nil
                } else {
                    pendingMermaid?.source.append(runText)
                }
                continue
            }

            // Leaving a mermaid block: flush it before processing the
            // next run so the trailing `\n\n` separator lands first.
            if let pending = pendingMermaid {
                flushMermaid(
                    pending, into: result, theme: theme,
                    images: mermaidImages, widthCache: widthCache
                )
                pendingMermaid = nil
                lastBlockKey = nil
            }

            // Inline markdown images (`![alt](url)`). Foundation tags the
            // run with `imageURL`; we replace the alt-text run with a
            // resizable figure attachment so the user can hover-drag a
            // width handle the same way they can on mermaid diagrams.
            // If we're mid-table, flush it first — placing an inline
            // attachment inside an `NSTextTable` cell stack would land
            // it on its own line outside the row.
            if let imageURL = run.imageURL {
                if let existing = pendingTable {
                    flushTable(existing, into: result, theme: theme)
                    pendingTable = nil
                    result.append(NSAttributedString(
                        string: "\n\n", attributes: theme.bodyAttributes
                    ))
                }
                let resolved = resolveImageURL(imageURL, against: baseURL)
                flushImage(
                    resolved: resolved,
                    into: result,
                    theme: theme,
                    images: markdownImages,
                    widthCache: widthCache
                )
                lastBlockKey = nil
                continue
            }

            let tableInfo = tableInfo(from: run.presentationIntent)

            if let info = tableInfo {
                // Finished one table, starting a different one: flush
                // the previous before opening the new accumulator.
                if let existing = pendingTable, existing.identity != info.tableIdentity {
                    flushTable(existing, into: result, theme: theme)
                    pendingTable = nil
                    lastBlockKey = nil
                }
                if pendingTable == nil {
                    if result.length > 0 {
                        result.append(NSAttributedString(
                            string: "\n\n", attributes: theme.bodyAttributes
                        ))
                    }
                    pendingTable = TableAccumulator(
                        identity: info.tableIdentity,
                        columns: info.columnCount
                    )
                }
                let attrs = theme.attributes(
                    for: run.inlinePresentationIntent,
                    block: run.presentationIntent
                )
                pendingTable?.append(
                    rowKind: info.rowKind,
                    column: info.cellColumn,
                    text: runText,
                    attrs: attrs
                )
                continue
            }

            // Leaving a table: flush it, then insert a block gap so
            // the following block starts on its own paragraph.
            if let existing = pendingTable {
                flushTable(existing, into: result, theme: theme)
                pendingTable = nil
                result.append(NSAttributedString(
                    string: "\n\n", attributes: theme.bodyAttributes
                ))
                lastBlockKey = nil
            }

            // Insert a block boundary if this run is in a different
            // block from the previous one. PresentationIntent doesn't
            // expose a single identity — it's a stack of components,
            // each with its own — so we compare the full identity path.
            if let intent = run.presentationIntent {
                let key = intent.components.map(\.identity)
                if let last = lastBlockKey, last != key {
                    result.append(NSAttributedString(
                        string: "\n\n",
                        attributes: theme.bodyAttributes
                    ))
                }
                lastBlockKey = key
            }

            let attrs = theme.attributes(
                for: run.inlinePresentationIntent,
                block: run.presentationIntent
            )
            result.append(NSAttributedString(string: runText, attributes: attrs))
        }

        if let existing = pendingTable {
            flushTable(existing, into: result, theme: theme)
        }
        if let pending = pendingMermaid {
            flushMermaid(
                pending, into: result, theme: theme,
                images: mermaidImages, widthCache: widthCache
            )
        }

        if typography.leadingBold {
            BionicReading.emphasize(result)
        }

        return result
    }

    // MARK: Mermaid extraction

    private struct MermaidCodeBlockInfo {
        let identity: Int
    }

    /// Returns metadata for a run that lives inside a fenced code block
    /// whose language hint is "mermaid" (case-insensitive). Anything
    /// else — including unlabeled or differently-tagged code — falls
    /// back to the standard styled-code path.
    private static func mermaidCodeBlockInfo(
        from intent: PresentationIntent?
    ) -> MermaidCodeBlockInfo? {
        guard let intent else { return nil }
        for component in intent.components {
            if case .codeBlock(let language) = component.kind,
               language?.lowercased() == "mermaid" {
                return MermaidCodeBlockInfo(identity: component.identity)
            }
        }
        return nil
    }

    private static func flushMermaid(
        _ pending: (identity: Int, source: String),
        into result: NSMutableAttributedString,
        theme: Theme,
        images: [String: NSImage],
        widthCache: FigureWidthCache?
    ) {
        // Strip the trailing newline that Foundation includes in code-
        // block content; preserving it would shove the attachment onto
        // its own line below the diagram.
        var source = pending.source
        while source.hasSuffix("\n") { source.removeLast() }

        if result.length > 0,
           !result.string.hasSuffix("\n\n") {
            result.append(NSAttributedString(
                string: "\n\n", attributes: theme.bodyAttributes
            ))
        }

        let resolvedImage = images[source]
        let placeholder = mermaidPlaceholderImage()
        let displayImage = resolvedImage ?? placeholder
        let aspect = max(0.1, displayImage.size.width / max(1, displayImage.size.height))
        // Slightly narrower than the column so the resize handle has
        // breathing room on the trailing edge.
        let baseline = min(560, displayImage.size.width)

        let figureID = "mermaid:" + stableHash(of: source)
        let attachment = ResizableFigureAttachment(
            figureID: figureID,
            baselineWidth: baseline,
            aspect: aspect,
            widthCache: widthCache
        ) {
            // Resolved image takes precedence; placeholder is reused
            // until the WKWebView snapshot lands.
            return images[source] ?? placeholder
        }

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.paragraphSpacingBefore = 8
        para.paragraphSpacing = 8

        let attachmentString = NSMutableAttributedString(attachment: attachment)
        let fullRange = NSRange(location: 0, length: attachmentString.length)
        attachmentString.addAttributes(
            [
                .readAloudTTSMermaidSource: source,
                .paragraphStyle: para,
                .foregroundColor: NSColor.labelColor,
            ],
            range: fullRange
        )
        result.append(attachmentString)
        // Trailing newline so the next block starts on its own line.
        result.append(NSAttributedString(
            string: "\n", attributes: theme.bodyAttributes
        ))
    }

    /// Emits a `ResizableFigureAttachment` for a markdown `![alt](url)`
    /// image. The actual image is loaded asynchronously by the reader
    /// view; until then we paint a generic placeholder so layout still
    /// claims the right vertical space.
    private static func flushImage(
        resolved: URL,
        into result: NSMutableAttributedString,
        theme: Theme,
        images: [URL: NSImage],
        widthCache: FigureWidthCache?
    ) {
        if result.length > 0,
           !result.string.hasSuffix("\n\n") {
            result.append(NSAttributedString(
                string: "\n\n", attributes: theme.bodyAttributes
            ))
        }

        let resolvedImage = images[resolved]
        let placeholder = imagePlaceholder(for: resolved)
        let displayImage = resolvedImage ?? placeholder
        let aspect = max(0.1, displayImage.size.width / max(1, displayImage.size.height))
        let baseline = min(560, max(240, displayImage.size.width))

        let figureID = "img:" + resolved.absoluteString
        let attachment = ResizableFigureAttachment(
            figureID: figureID,
            baselineWidth: baseline,
            aspect: aspect,
            widthCache: widthCache
        ) {
            return images[resolved] ?? placeholder
        }

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.paragraphSpacingBefore = 8
        para.paragraphSpacing = 8

        let attachmentString = NSMutableAttributedString(attachment: attachment)
        let fullRange = NSRange(location: 0, length: attachmentString.length)
        attachmentString.addAttributes(
            [
                .readAloudTTSMarkdownImageURL: resolved,
                .paragraphStyle: para,
                .foregroundColor: NSColor.labelColor,
            ],
            range: fullRange
        )
        result.append(attachmentString)
        result.append(NSAttributedString(
            string: "\n", attributes: theme.bodyAttributes
        ))
    }

    /// Resolves a markdown image URL — which may be a relative path
    /// like `figures/screenshot.png` — against the markdown file's
    /// directory. Returns the input unchanged for already-absolute URLs.
    private static func resolveImageURL(_ url: URL, against baseURL: URL?) -> URL {
        if url.scheme != nil { return url }
        guard let baseURL else { return url }
        // `URL(string:relativeTo:)` won't take an existing URL value;
        // use the path components instead so we tolerate both relative
        // strings parsed as URLs and bare paths.
        let raw = url.relativePath.isEmpty ? url.path : url.relativePath
        return URL(fileURLWithPath: raw, relativeTo: baseURL).standardized
    }

    /// Soft band shown until the markdown image loads. Mirrors the
    /// mermaid placeholder dimensions so layout thrash is bounded when
    /// the real image lands.
    private static func imagePlaceholder(for url: URL) -> NSImage {
        let size = NSSize(width: 520, height: 320)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.secondaryLabelColor.withAlphaComponent(0.06).setFill()
        NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: size),
            xRadius: 10, yRadius: 10
        ).fill()

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .paragraphStyle: para,
        ]
        let label = url.lastPathComponent as NSString
        let textHeight: CGFloat = 16
        let textRect = NSRect(
            x: 0, y: (size.height - textHeight) / 2,
            width: size.width, height: textHeight
        )
        label.draw(in: textRect, withAttributes: attrs)
        return image
    }

    /// Stable, version-independent hash usable as a figure id key.
    /// `String.hashValue` is salted per-process and would re-key the
    /// width cache on every launch; a small djb2 keeps the same source
    /// mapped to the same id across sessions.
    private static func stableHash(of input: String) -> String {
        var hash: UInt64 = 5381
        for byte in input.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    /// Soft "Rendering diagram…" tile shown until the WKWebView
    /// snapshot resolves. Sized so it occupies a clearly-visible band
    /// of the column instead of a tiny inline glyph.
    private static func mermaidPlaceholderImage() -> NSImage {
        let size = NSSize(width: 520, height: 88)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let bg = NSColor.secondaryLabelColor.withAlphaComponent(0.08)
        bg.setFill()
        NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: size),
            xRadius: 10, yRadius: 10
        ).fill()

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: para,
        ]
        let text = "Rendering Mermaid diagram…" as NSString
        let textHeight: CGFloat = 18
        let textRect = NSRect(
            x: 0,
            y: (size.height - textHeight) / 2,
            width: size.width,
            height: textHeight
        )
        text.draw(in: textRect, withAttributes: attrs)
        return image
    }

    // MARK: Table extraction

    private struct TableRunInfo {
        let tableIdentity: Int
        let columnCount: Int
        let rowKind: TableRowKind
        let cellColumn: Int
    }

    private enum TableRowKind: Hashable {
        case header
        case data(Int)

        /// Deterministic sort order for flushing rows in the correct
        /// visual sequence: header first, then data rows by index.
        var sortOrder: Int {
            switch self {
            case .header: return -1
            case .data(let i): return i
            }
        }
    }

    private static func tableInfo(
        from intent: PresentationIntent?
    ) -> TableRunInfo? {
        guard let intent else { return nil }
        var tableIdentity: Int?
        var columnCount: Int?
        var rowKind: TableRowKind?
        var cellColumn: Int?

        // Components are outer-first; iterate all so we're insensitive
        // to whichever end the innermost .tableCell lives on.
        for component in intent.components {
            switch component.kind {
            case .table(let columns):
                tableIdentity = component.identity
                columnCount = columns.count
            case .tableHeaderRow:
                rowKind = .header
            case .tableRow(let rowIndex):
                rowKind = .data(rowIndex)
            case .tableCell(let columnIndex):
                cellColumn = columnIndex
            default:
                break
            }
        }
        guard let tableIdentity, let columnCount, let rowKind, let cellColumn else {
            return nil
        }
        return TableRunInfo(
            tableIdentity: tableIdentity,
            columnCount: columnCount,
            rowKind: rowKind,
            cellColumn: cellColumn
        )
    }

    // MARK: Table accumulation + flushing

    private final class TableAccumulator {
        let identity: Int
        let columns: Int
        private(set) var rowOrder: [TableRowKind] = []
        /// Accumulated per-cell rich text. Indexed first by row, then
        /// by column; empty cells stay absent and render as blank.
        private(set) var cells: [TableRowKind: [Int: NSMutableAttributedString]] = [:]

        init(identity: Int, columns: Int) {
            self.identity = identity
            self.columns = columns
        }

        func append(
            rowKind: TableRowKind,
            column: Int,
            text: String,
            attrs: [NSAttributedString.Key: Any]
        ) {
            if cells[rowKind] == nil {
                cells[rowKind] = [:]
                rowOrder.append(rowKind)
            }
            let existing = cells[rowKind]?[column] ?? NSMutableAttributedString()
            existing.append(NSAttributedString(string: text, attributes: attrs))
            cells[rowKind]?[column] = existing
        }
    }

    private static func flushTable(
        _ accumulator: TableAccumulator,
        into result: NSMutableAttributedString,
        theme: Theme
    ) {
        guard !accumulator.rowOrder.isEmpty, accumulator.columns > 0 else { return }

        let table = NSTextTable()
        table.numberOfColumns = accumulator.columns
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.collapsesBorders = true
        table.hidesEmptyCells = false
        // Each cell block occupies an equal share of the table width.
        // `automaticLayoutAlgorithm` honors percentage hints on blocks
        // as a preferred width and still flows long text with wrapping.
        let perColumnPercent = 100.0 / CGFloat(accumulator.columns)

        // Sort rows so header lands first regardless of emission order,
        // then data rows by their reported index.
        let orderedRows = accumulator.rowOrder.sorted {
            $0.sortOrder < $1.sortOrder
        }
        let dividerColor = NSColor.separatorColor

        for (nsRow, rowKind) in orderedRows.enumerated() {
            let rowID = UUID().uuidString
            let cellsInRow = accumulator.cells[rowKind] ?? [:]

            for col in 0..<accumulator.columns {
                let block = NSTextTableBlock(
                    table: table,
                    startingRow: nsRow,
                    rowSpan: 1,
                    startingColumn: col,
                    columnSpan: 1
                )
                block.setContentWidth(perColumnPercent, type: .percentageValueType)
                // Interior spacing: a little breathing room so cell
                // text doesn't collide with the horizontal dividers.
                block.setWidth(6, type: .absoluteValueType, for: .padding)
                block.setWidth(10, type: .absoluteValueType, for: .padding, edge: .minX)
                block.setWidth(10, type: .absoluteValueType, for: .padding, edge: .maxX)
                // Horizontal-only dividers: bottom edge of every cell.
                // `collapsesBorders` merges with the next row's top —
                // since we don't draw a top border, no overlap exists.
                block.setWidth(0, type: .absoluteValueType, for: .border)
                block.setWidth(0.5, type: .absoluteValueType, for: .border, edge: .maxY)
                block.setBorderColor(dividerColor)

                let cellParagraph = NSMutableParagraphStyle()
                cellParagraph.textBlocks = [block]
                cellParagraph.lineHeightMultiple = 1.25

                let cellContent = NSMutableAttributedString()
                if let existing = cellsInRow[col] {
                    cellContent.append(existing)
                }
                // Paragraph terminator lives inside the cell so
                // NSTextTable treats the whole cell as one logical
                // paragraph owned by this block.
                cellContent.append(NSAttributedString(string: "\n"))

                let fullRange = NSRange(location: 0, length: cellContent.length)
                cellContent.addAttribute(
                    .paragraphStyle, value: cellParagraph, range: fullRange
                )
                cellContent.addAttribute(
                    .readAloudTTSTableRowID, value: rowID, range: fullRange
                )
                // Backfill font/color on the terminator or on any
                // empty cell placeholder so NSTextView has concrete
                // attributes to lay out against.
                cellContent.enumerateAttribute(
                    .font, in: fullRange, options: []
                ) { value, subRange, _ in
                    if value == nil {
                        let fallbackFont: NSFont = (rowKind == .header)
                            ? theme.bodyBold
                            : theme.body
                        cellContent.addAttribute(
                            .font, value: fallbackFont, range: subRange
                        )
                    }
                }
                cellContent.enumerateAttribute(
                    .foregroundColor, in: fullRange, options: []
                ) { value, subRange, _ in
                    if value == nil {
                        cellContent.addAttribute(
                            .foregroundColor,
                            value: NSColor.labelColor,
                            range: subRange
                        )
                    }
                }

                result.append(cellContent)
            }
        }
    }

    private struct Theme {
        let body: NSFont
        let bodyBold: NSFont
        let bodyItalic: NSFont
        let bodyBoldItalic: NSFont
        let mono: NSFont
        let monoBold: NSFont
        let h1: NSFont
        let h2: NSFont
        let h3: NSFont
        let h4: NSFont

        let bodyAttributes: [NSAttributedString.Key: Any]

        init(scale: Double = 1.0, typography: ReaderTypography = ReaderTypography()) {
            let s = CGFloat(scale)
            let bodyBase = typography.baseFont(size: 16 * s)
            let manager = NSFontManager.shared
            self.body = bodyBase
            self.bodyBold = manager.convert(bodyBase, toHaveTrait: .boldFontMask)
            self.bodyItalic = manager.convert(bodyBase, toHaveTrait: .italicFontMask)
            self.bodyBoldItalic = manager.convert(bodyBold, toHaveTrait: .italicFontMask)
            self.mono = NSFont.monospacedSystemFont(ofSize: 13 * s, weight: .regular)
            self.monoBold = NSFont.monospacedSystemFont(ofSize: 13 * s, weight: .bold)

            let h1Base = typography.baseFont(size: 28 * s)
            let h2Base = typography.baseFont(size: 22 * s)
            let h3Base = typography.baseFont(size: 18 * s)
            let h4Base = typography.baseFont(size: 16 * s)
            self.h1 = manager.convert(h1Base, toHaveTrait: .boldFontMask)
            self.h2 = manager.convert(h2Base, toHaveTrait: .boldFontMask)
            self.h3 = manager.convert(h3Base, toHaveTrait: .boldFontMask)
            self.h4 = manager.convert(h4Base, toHaveTrait: .boldFontMask)

            let para = typography.paragraphStyle(paragraphSpacing: 6)

            var attrs: [NSAttributedString.Key: Any] = [
                .font: bodyBase,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: para,
            ]
            if let kern = typography.kern {
                attrs[.kern] = kern
            }
            self.bodyAttributes = attrs
        }

        func attributes(
            for inline: InlinePresentationIntent?,
            block: PresentationIntent?
        ) -> [NSAttributedString.Key: Any] {
            var attrs = bodyAttributes

            // Block-level overrides come first so inline italics on a
            // heading still apply on top of the heading font.
            var blockKind: BlockKind = .paragraph
            if let block {
                for component in block.components {
                    switch component.kind {
                    case .header(let level):
                        blockKind = .header(level)
                        attrs[.font] = headerFont(for: level)
                    case .codeBlock:
                        blockKind = .codeBlock
                        attrs[.font] = mono
                        attrs[.foregroundColor] = NSColor.secondaryLabelColor
                    case .blockQuote:
                        blockKind = .blockQuote
                        attrs[.foregroundColor] = NSColor.secondaryLabelColor
                    case .tableHeaderRow:
                        blockKind = .tableHeader
                        attrs[.font] = bodyBold
                    default:
                        break
                    }
                }
            }

            if let inline {
                if inline.contains(.code), blockKind != .codeBlock {
                    attrs[.font] = mono
                    attrs[.foregroundColor] = NSColor.secondaryLabelColor
                }
                let isStrong = inline.contains(.stronglyEmphasized)
                let isEm = inline.contains(.emphasized)
                if isStrong || isEm, blockKind == .paragraph || blockKind == .blockQuote {
                    switch (isStrong, isEm) {
                    case (true, true):  attrs[.font] = bodyBoldItalic
                    case (true, false): attrs[.font] = bodyBold
                    case (false, true): attrs[.font] = bodyItalic
                    default: break
                    }
                } else if isEm, blockKind == .tableHeader {
                    // Header row is already bold; italic emphasis
                    // upgrades it to bold-italic rather than plain italic.
                    attrs[.font] = bodyBoldItalic
                }
            }

            return attrs
        }

        private func headerFont(for level: Int) -> NSFont {
            switch level {
            case 1:  return h1
            case 2:  return h2
            case 3:  return h3
            default: return h4
            }
        }

        private enum BlockKind: Equatable {
            case paragraph
            case header(Int)
            case codeBlock
            case blockQuote
            case tableHeader
        }
    }
}

// MARK: - NSTextView hosts

private struct MarkdownTextView: NSViewRepresentable {
    let attributed: NSAttributedString
    let activeSentence: Sentence?
    let spokenSubRange: NSRange?
    let searchMatches: [NSRange]
    let currentMatchIndex: Int
    let readingTheme: ReadingTheme
    let onReadFromOffset: (Int) -> Void

    final class Coordinator {
        /// ObjectIdentifier of the most-recently-assigned attributed
        /// string. Used as a cheap content-identity check so we only
        /// reassign text storage when the document actually changes —
        /// `storage.string` equality is O(N) and was the main cost
        /// on every highlight tick for large markdown files.
        var lastAttributedIdentity: ObjectIdentifier?
        /// Range of the previous sentence wash — we remove attributes
        /// from just that range on the next tick instead of scanning
        /// the full storage, which was the second hot spot.
        var lastSentenceRange: NSRange?
        /// Range of the previous word-level sub-highlight.
        var lastSubRange: NSRange?
        /// Last sentence index we auto-scrolled to. Scrolling only
        /// fires on index change, not every spokenSubRange word tick,
        /// so the user can scroll manually without the viewport
        /// snapping back every second.
        var lastScrolledSentenceIndex: Int?
        /// Ranges last painted as search results — cleared incrementally
        /// when the query/options/match-set change.
        var lastSearchRanges: [NSRange] = []
        var lastCurrentSearchRange: NSRange?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        makeReadOnlyTextScrollView(onReadFromOffset: onReadFromOffset)
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? ClickableReaderTextView,
              let storage = tv.textStorage else { return }

        tv.onReadFromOffset = onReadFromOffset
        readingTheme.apply(toScrollView: nsView, textView: tv)

        let identity = ObjectIdentifier(attributed)
        if context.coordinator.lastAttributedIdentity != identity {
            storage.setAttributedString(attributed)
            context.coordinator.lastAttributedIdentity = identity
            context.coordinator.lastSentenceRange = nil
            context.coordinator.lastSubRange = nil
            context.coordinator.lastScrolledSentenceIndex = nil
            context.coordinator.lastSearchRanges = []
            context.coordinator.lastCurrentSearchRange = nil
        }

        applyHighlightIncremental(
            to: tv,
            storage: storage,
            coordinator: context.coordinator,
            sentence: activeSentence,
            spokenSubRange: spokenSubRange
        )

        applySearchHighlights(
            to: tv,
            storage: storage,
            coordinator: context.coordinator,
            matches: searchMatches,
            currentIndex: currentMatchIndex
        )
    }
}

/// Editable markdown source view. Backed by a non-clickable
/// NSTextView with `isEditable = true` and `allowsUndo = true` so
/// AppKit hands us \u{2318}Z / \u{21E7}\u{2318}Z for free. Every
/// change is mirrored into `MarkdownDocumentStore` so the dirty dot,
/// preview re-render, and quit warning all observe the same state.
private struct EditableSourceTextView: NSViewRepresentable {
    let url: URL
    let searchMatches: [NSRange]
    let currentMatchIndex: Int
    let fontScale: Double

    final class Coordinator: NSObject, NSTextViewDelegate {
        let url: URL
        let store: MarkdownDocumentStore
        var ignoreNextChange: Bool = false
        /// Search-match ranges last painted, for incremental clears.
        var lastSearchRanges: [NSRange] = []
        var lastCurrentSearchRange: NSRange?
        /// Per-view undo manager so text-edit undo invocations die with
        /// the NSTextView. Without this, AppKit registers undo on the
        /// window's UndoManager, which outlives the view and crashes
        /// in `_undoRedoTextOperation:` when the storage is freed.
        let textUndoManager: UndoManager

        @MainActor
        init(url: URL, store: MarkdownDocumentStore) {
            self.url = url
            self.store = store
            self.textUndoManager = UndoManager()
        }

        func textDidChange(_ notification: Notification) {
            guard !ignoreNextChange,
                  let tv = notification.object as? NSTextView else {
                return
            }
            store.update(url: url, text: tv.string)
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            textUndoManager
        }
    }

    @MainActor
    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, store: MarkdownDocumentStore.shared)
    }

    @MainActor
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(Color.readAloudTTSSurface)

        let tv = NSTextView()
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = NSFont.monospacedSystemFont(
            ofSize: 13 * CGFloat(fontScale), weight: .regular
        )
        tv.textColor = NSColor.labelColor
        tv.backgroundColor = NSColor(Color.readAloudTTSSurface)
        tv.drawsBackground = true
        tv.textContainerInset = NSSize(width: 32, height: 24)
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude
        )
        tv.delegate = context.coordinator
        // Smart substitutions break code samples + markdown syntax.
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false

        let initial = MarkdownDocumentStore.shared.currentText(url: url) ?? ""
        context.coordinator.ignoreNextChange = true
        tv.string = initial
        context.coordinator.ignoreNextChange = false
        context.coordinator.textUndoManager.removeAllActions()

        scroll.documentView = tv
        return scroll
    }

    @MainActor
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView,
              let storage = tv.textStorage else { return }

        // Pick up font-scale changes from ⌘+ / ⌘- without rebuilding
        // the view. Only reassign when the size actually drifted so
        // typing-time work is still O(1).
        let desiredSize = 13 * CGFloat(fontScale)
        if let current = tv.font, current.pointSize != desiredSize {
            let next = NSFont.monospacedSystemFont(
                ofSize: desiredSize, weight: .regular
            )
            tv.font = next
            tv.typingAttributes[.font] = next
            // The whole storage shares one font; restyle in one pass.
            storage.beginEditing()
            storage.addAttribute(
                .font, value: next,
                range: NSRange(location: 0, length: storage.length)
            )
            storage.endEditing()
        }

        // Pull the latest buffer from the store so external changes
        // (Cmd+Z deep into a snapshot, "Discard" from the close sheet,
        // or a fresh load) propagate back into the visible text — but
        // skip the assignment when the strings already match so we
        // don't clobber the user's selection on every keystroke.
        let buffer = MarkdownDocumentStore.shared.currentText(url: url) ?? ""
        if tv.string != buffer {
            context.coordinator.ignoreNextChange = true
            tv.string = buffer
            context.coordinator.ignoreNextChange = false
            // External buffer change: drop pending undo so ⌘Z can't
            // try to roll back into bytes the user never typed.
            context.coordinator.textUndoManager.removeAllActions()
            // Reassigning `string` strips attributes, so any search
            // highlights need to be repainted from scratch.
            context.coordinator.lastSearchRanges = []
            context.coordinator.lastCurrentSearchRange = nil
        }

        applySearchHighlightsRaw(
            storage: storage,
            textView: tv,
            lastRanges: &context.coordinator.lastSearchRanges,
            lastCurrent: &context.coordinator.lastCurrentSearchRange,
            matches: searchMatches,
            currentIndex: currentMatchIndex
        )
    }
}

// MARK: - Shared scrolling text view setup

@MainActor
private func makeReadOnlyTextScrollView(
    onReadFromOffset: ((Int) -> Void)?
) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = false
    scroll.borderType = .noBorder
    scroll.drawsBackground = true
    scroll.backgroundColor = NSColor(Color.readAloudTTSSurface)

    // Make sure AppKit knows how to vend our custom view provider for
    // attachments tagged with `kResizableFigureFileType`. Idempotent.
    registerResizableFigureProvider()

    // The canonical TextKit 2 opt-in (WWDC22 "What's new in TextKit").
    // Plain `NSTextView()` defaults to TextKit 1 on macOS, which never
    // instantiates `NSTextAttachmentViewProvider`. Subclasses inherit
    // this convenience initializer.
    let textView: NSTextView
    if let onReadFromOffset {
        let clickable = ClickableReaderTextView(usingTextLayoutManager: true)
        clickable.onReadFromOffset = onReadFromOffset
        textView = clickable
    } else {
        textView = NSTextView(usingTextLayoutManager: true)
    }
    textView.isEditable = false
    textView.isSelectable = true
    textView.isRichText = true
    textView.backgroundColor = NSColor(Color.readAloudTTSSurface)
    textView.drawsBackground = true
    textView.textContainerInset = NSSize(width: 32, height: 24)
    textView.autoresizingMask = [.width]
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.containerSize = NSSize(
        width: 0, height: CGFloat.greatestFiniteMagnitude
    )

    Logger(subsystem: "app.readaloudtts.mac", category: "resizable-figure")
        .debug("preview NSTextView using TK2 = \(textView.textLayoutManager != nil)")

    scroll.documentView = textView
    return scroll
}

/// Incremental highlight updater. Two big wins over the naive
/// "remove all, re-apply" pass that was running on every
/// `spokenSubRange` tick from the Whisper aligner:
///
/// 1. **Bounded clears.** We only strip the background from the
///    range we previously painted, not the full document. On a
///    100k-character markdown file the full clear walked every
///    attribute run; the bounded clear is O(ranges we touched).
/// 2. **Scroll-only-on-sentence-change.** `scrollRangeToVisible`
///    fired on every word tick, yanking the viewport back while the
///    user was mid-scroll. Now it only fires when the sentence
///    index changes — manual scrolling during playback finally
///    works.
@MainActor
private func applyHighlightIncremental(
    to textView: NSTextView,
    storage: NSTextStorage,
    coordinator: MarkdownTextView.Coordinator,
    sentence: Sentence?,
    spokenSubRange: NSRange?
) {
    storage.beginEditing()

    // Clear the previously-highlighted ranges (bounded), not the
    // whole document.
    if let last = coordinator.lastSubRange,
       NSMaxRange(last) <= storage.length {
        storage.removeAttribute(.backgroundColor, range: last)
    }
    if let last = coordinator.lastSentenceRange,
       NSMaxRange(last) <= storage.length {
        storage.removeAttribute(.backgroundColor, range: last)
    }

    guard let sentence else {
        coordinator.lastSentenceRange = nil
        coordinator.lastSubRange = nil
        storage.endEditing()
        return
    }

    let sentenceRange = NSRange(
        location: sentence.offsetInBlock,
        length: sentence.lengthInBlock
    )
    guard NSMaxRange(sentenceRange) <= storage.length else {
        coordinator.lastSentenceRange = nil
        coordinator.lastSubRange = nil
        storage.endEditing()
        return
    }

    let soft = HighlightStyle.current.sentenceBand
    storage.addAttribute(.backgroundColor, value: soft, range: sentenceRange)
    coordinator.lastSentenceRange = sentenceRange

    if let sub = spokenSubRange {
        let subOrigin = sentence.offsetInBlock + sub.location
        let subRange = NSRange(location: subOrigin, length: sub.length)
        if NSMaxRange(subRange) <= storage.length {
            let bright = HighlightStyle.current.activeWord
            storage.addAttribute(.backgroundColor, value: bright, range: subRange)
            coordinator.lastSubRange = subRange
        } else {
            coordinator.lastSubRange = nil
        }
    } else {
        coordinator.lastSubRange = nil
    }

    storage.endEditing()

    // Only scroll when the *sentence* changes. Word-level ticks from
    // the aligner don't pull the viewport any more; the user's
    // manual scroll wheel / trackpad stays in charge.
    let currentIndex = sentence.offsetInBlock
    if coordinator.lastScrolledSentenceIndex != currentIndex {
        coordinator.lastScrolledSentenceIndex = currentIndex
        textView.scrollRangeToVisible(sentenceRange)
    }
}

// MARK: - Search highlights

/// Yellow background that visually separates from the orange playback
/// wash. Drawn after the playback paint so on overlap the user can
/// still tell where the matches are.
private let searchMatchColor = NSColor.systemYellow.withAlphaComponent(0.45)
private let searchCurrentMatchColor = NSColor.systemYellow.withAlphaComponent(0.85)

/// Clears the previously-painted search ranges, paints fresh
/// highlights for the new match set, and scrolls the current match
/// into view. Used by the Preview view so its coordinator can keep
/// the rest of its caching logic intact.
@MainActor
private func applySearchHighlights(
    to textView: NSTextView,
    storage: NSTextStorage,
    coordinator: MarkdownTextView.Coordinator,
    matches: [NSRange],
    currentIndex: Int
) {
    applySearchHighlightsRaw(
        storage: storage,
        textView: textView,
        lastRanges: &coordinator.lastSearchRanges,
        lastCurrent: &coordinator.lastCurrentSearchRange,
        matches: matches,
        currentIndex: currentIndex
    )
}

/// Lower-level shared implementation reused by both the Preview and
/// Source text views. Operates only on the storage's attributes — the
/// bounded clear keeps the cost proportional to the number of visible
/// matches, not document length.
@MainActor
private func applySearchHighlightsRaw(
    storage: NSTextStorage,
    textView: NSTextView,
    lastRanges: inout [NSRange],
    lastCurrent: inout NSRange?,
    matches: [NSRange],
    currentIndex: Int
) {
    storage.beginEditing()
    defer { storage.endEditing() }

    let length = storage.length
    for range in lastRanges where NSMaxRange(range) <= length {
        storage.removeAttribute(.underlineStyle, range: range)
        storage.removeAttribute(.underlineColor, range: range)
    }
    if let last = lastCurrent, NSMaxRange(last) <= length {
        storage.removeAttribute(.backgroundColor, range: last)
    }
    lastRanges = []
    lastCurrent = nil

    guard !matches.isEmpty else { return }

    for range in matches where NSMaxRange(range) <= length {
        storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        storage.addAttribute(.underlineColor, value: searchMatchColor, range: range)
    }
    lastRanges = matches.filter { NSMaxRange($0) <= length }

    guard currentIndex >= 0, currentIndex < matches.count else { return }
    let current = matches[currentIndex]
    if NSMaxRange(current) <= length {
        storage.addAttribute(.backgroundColor, value: searchCurrentMatchColor, range: current)
        lastCurrent = current
        // Defer the scroll so it runs after the storage edit
        // completes; calling scrollRangeToVisible inside the begin/end
        // pair occasionally races AppKit's internal layout pass.
        DispatchQueue.main.async { [weak textView] in
            textView?.scrollRangeToVisible(current)
        }
    }
}

// MARK: - Mermaid rendering

/// Renders Mermaid source to a static `NSImage` via a hidden
/// WKWebView. The web view loads `mermaid.min.js` from a public CDN,
/// runs `mermaid.render(...)` to materialize SVG, and we snapshot the
/// rendered DOM at its natural bounding box. The renderer is a
/// singleton so we can fan out parallel renders (one webview each) and
/// share the message handler plumbing across them.
@MainActor
final class MermaidWebRenderer: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let shared = MermaidWebRenderer()

    private static let log = Logger(subsystem: "app.readaloudtts.mac", category: "mermaid")

    private struct Pending {
        let continuation: CheckedContinuation<NSImage, Error>
        /// We keep a reference to the host window so it survives until
        /// the snapshot completes; releasing it earlier deallocates the
        /// content view mid-flight and the snapshot returns nil.
        let window: NSWindow
        let webView: WKWebView
    }

    private var pending: [ObjectIdentifier: Pending] = [:]

    enum MermaidError: Error, LocalizedError {
        case renderFailed(String)
        case snapshotFailed
        case invalidPayload

        var errorDescription: String? {
            switch self {
            case .renderFailed(let message): return "mermaid render error: \(message)"
            case .snapshotFailed: return "mermaid snapshot failed"
            case .invalidPayload: return "mermaid render returned an invalid payload"
            }
        }
    }

    func render(source: String) async throws -> NSImage {
        try await withCheckedThrowingContinuation { continuation in
            startRender(source: source, continuation: continuation)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Self.log.info("mermaid webview didFinish navigation")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Self.log.error("mermaid webview didFail: \(error.localizedDescription, privacy: .public)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Self.log.error("mermaid webview provisional fail: \(error.localizedDescription, privacy: .public)")
    }

    private func startRender(
        source: String,
        continuation: CheckedContinuation<NSImage, Error>
    ) {
        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        userContent.add(self, name: "readAloudTTSMermaid")
        userContent.add(self, name: "readAloudTTSMermaidLog")
        config.userContentController = userContent
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        let initialFrame = NSRect(x: 0, y: 0, width: 1400, height: 1400)
        let webView = WKWebView(frame: initialFrame, configuration: config)
        webView.navigationDelegate = self

        // The web view must live in a window for snapshotting to
        // produce non-blank pixels on macOS. Position the host window
        // far off-screen so it never flashes for the user.
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000,
                                width: initialFrame.width,
                                height: initialFrame.height),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.orderBack(nil)

        let id = ObjectIdentifier(webView)
        pending[id] = Pending(
            continuation: continuation, window: window, webView: webView
        )

        // Load the bundled mermaid.min.js as a data URL embedded
        // inside the HTML so we don't depend on network reachability
        // or App Sandbox network permissions at render time.
        let mermaidJS = Self.loadBundledMermaidJS()
        let html = Self.makeHTML(source: source, mermaidScript: mermaidJS)
        // Use the bundle as base so any same-origin asset relative
        // URLs can resolve (mermaid is self-contained, but the base
        // URL also dictates the security origin for postMessage).
        let baseURL = Bundle.main.resourceURL ?? URL(fileURLWithPath: "/")
        webView.loadHTMLString(html, baseURL: baseURL)

        // Hard timeout: if we don't hear back, fail the continuation
        // with a clear error so the placeholder isn't stuck forever.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, let task = self.pending[id] else { return }
            Self.log.error("mermaid render timed out for source of length \(source.count, privacy: .public)")
            self.finish(
                task: task, id: id,
                result: .failure(MermaidError.renderFailed("timed out after 15s"))
            )
        }
    }

    private static func loadBundledMermaidJS() -> String {
        guard let url = Bundle.main.url(
            forResource: "mermaid.min", withExtension: "js"
        ) else {
            log.error("mermaid.min.js missing from bundle")
            return ""
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            log.error(
                "failed to read mermaid.min.js: \(error.localizedDescription, privacy: .public)"
            )
            return ""
        }
    }

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        // WKWebView delivers script messages on the main thread but
        // `WKScriptMessage`'s accessors are main-actor isolated, so we
        // assume isolation to read them, then hand the plain values
        // off to the actor-isolated handler.
        MainActor.assumeIsolated {
            let name = message.name
            let body = message.body
            let webView = message.webView
            self.handleMessage(name: name, body: body, webView: webView)
        }
    }

    private func handleMessage(
        name: String,
        body: Any,
        webView: WKWebView?
    ) {
        // Forwarded log messages from the page just go to os_log so
        // we can see what's happening inside the WKWebView.
        if name == "readAloudTTSMermaidLog" {
            let text = (body as? String) ?? String(describing: body)
            Self.log.info("mermaid-page: \(text, privacy: .public)")
            return
        }
        guard name == "readAloudTTSMermaid", let webView else { return }
        let id = ObjectIdentifier(webView)
        guard let task = pending[id] else { return }
        guard let payload = body as? [String: Any] else {
            finish(task: task, id: id, result: .failure(MermaidError.invalidPayload))
            return
        }

        if (payload["ok"] as? Bool) != true {
            let message = (payload["error"] as? String) ?? "unknown"
            finish(task: task, id: id, result: .failure(MermaidError.renderFailed(message)))
            return
        }

        let width = (payload["width"] as? CGFloat)
            ?? (payload["width"] as? Double).map { CGFloat($0) }
            ?? 600
        let height = (payload["height"] as? CGFloat)
            ?? (payload["height"] as? Double).map { CGFloat($0) }
            ?? 200

        let snapWidth = max(width, 16)
        let snapHeight = max(height, 16)
        webView.frame = NSRect(x: 0, y: 0, width: snapWidth, height: snapHeight)
        task.window.setContentSize(NSSize(width: snapWidth, height: snapHeight))

        // Give AppKit a tick to settle the resize before snapshotting,
        // otherwise the captured image occasionally clips at the old
        // (smaller) bounds.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            let snapConfig = WKSnapshotConfiguration()
            snapConfig.rect = NSRect(x: 0, y: 0, width: snapWidth, height: snapHeight)
            webView.takeSnapshot(with: snapConfig) { image, error in
                Task { @MainActor in
                    if let image {
                        self.finish(task: task, id: id, result: .success(image))
                    } else {
                        Self.log.error(
                            "snapshot failed: \(error?.localizedDescription ?? "nil", privacy: .public)"
                        )
                        self.finish(
                            task: task, id: id,
                            result: .failure(MermaidError.snapshotFailed)
                        )
                    }
                }
            }
        }
    }

    private func finish(
        task: Pending,
        id: ObjectIdentifier,
        result: Result<NSImage, Error>
    ) {
        pending.removeValue(forKey: id)
        task.window.contentView = nil
        task.window.orderOut(nil)
        switch result {
        case .success(let image): task.continuation.resume(returning: image)
        case .failure(let error): task.continuation.resume(throwing: error)
        }
    }

    private static func makeHTML(source: String, mermaidScript: String) -> String {
        let b64 = Data(source.utf8).base64EncodedString()
        // The Mermaid source is base64-encoded so it survives the
        // template substitution unchanged; the page decodes it with
        // `atob` and hands it to mermaid.render. The mermaid library
        // itself is also injected inline (read from the app bundle)
        // so we never depend on network reachability at render time.
        // We never inject mermaid output into the DOM via innerHTML —
        // the SVG returned by Mermaid is parsed with DOMParser and
        // appended as a node so there is no string concatenation into
        // HTML at runtime.
        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <style>
        html, body { margin: 0; padding: 0; background: white; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
        #wrapper { display: inline-block; padding: 16px; }
        #diagram svg { display: block; max-width: 1200px; height: auto; }
        #fallback { color: #b91c1c; padding: 16px; font: 13px ui-monospace, Menlo, monospace; white-space: pre-wrap; }
        </style>
        </head><body>
        <div id="wrapper"><div id="diagram"></div></div>
        <script>
        (function(){
          function bridgeLog(label){
            return function(){
              try {
                var parts = [];
                for (var i = 0; i < arguments.length; i++) {
                  parts.push(String(arguments[i]));
                }
                window.webkit.messageHandlers.readAloudTTSMermaidLog.postMessage(label + ': ' + parts.join(' '));
              } catch (e) {}
            };
          }
          window.console = window.console || {};
          var origError = console.error || function(){};
          console.log = bridgeLog('log');
          console.warn = bridgeLog('warn');
          console.error = bridgeLog('error');
          window.addEventListener('error', function(ev){
            try { window.webkit.messageHandlers.readAloudTTSMermaidLog.postMessage('window-error: ' + (ev.message || '?') + ' @ ' + (ev.filename || '') + ':' + (ev.lineno || '0')); } catch (e) {}
          });
          window.addEventListener('unhandledrejection', function(ev){
            try {
              var r = ev.reason;
              var msg = (r && r.message) ? r.message : String(r);
              window.webkit.messageHandlers.readAloudTTSMermaidLog.postMessage('unhandled: ' + msg);
            } catch (e) {}
          });
        })();
        </script>
        <script>
        \(mermaidScript)
        </script>
        <script>
        (async function(){
          function post(payload){
            try { window.webkit.messageHandlers.readAloudTTSMermaid.postMessage(payload); }
            catch (e) { console.error('post failed', e); }
          }
          function appendSvg(svgString){
            var parsed = new DOMParser().parseFromString(svgString, 'image/svg+xml');
            var node = parsed.documentElement;
            var target = document.getElementById('diagram');
            while (target.firstChild) target.removeChild(target.firstChild);
            target.appendChild(document.importNode(node, true));
          }
          try {
            if (typeof mermaid === 'undefined') {
              throw new Error('mermaid script did not load');
            }
            console.log('mermaid loaded, initializing');
            mermaid.initialize({ startOnLoad: false, theme: 'default', securityLevel: 'loose' });
            var src = atob('\(b64)');
            console.log('rendering, source length=' + src.length);
            var rendered = await mermaid.render('graphDiv', src);
            console.log('mermaid render returned svg length=' + (rendered && rendered.svg ? rendered.svg.length : 0));
            appendSvg(rendered.svg);
            // Off-screen WKWebView windows are treated as hidden by the
            // Page Visibility API, which suspends requestAnimationFrame.
            // setTimeout still fires, so use it to let layout settle
            // before measuring the bounding box.
            await new Promise(function(r){ setTimeout(r, 50); });
            var wrapper = document.getElementById('wrapper');
            var rect = wrapper.getBoundingClientRect();
            console.log('bbox ' + Math.ceil(rect.width) + 'x' + Math.ceil(rect.height));
            post({ ok: true, width: Math.ceil(rect.width), height: Math.ceil(rect.height) });
          } catch (e) {
            var msg = (e && e.message) ? e.message : String(e);
            console.error('render failed:', msg);
            var fallback = document.createElement('pre');
            fallback.id = 'fallback';
            fallback.textContent = 'Mermaid render failed: ' + msg;
            document.body.appendChild(fallback);
            post({ ok: false, error: msg });
          }
        })();
        </script>
        </body></html>
        """
    }
}
