import SwiftUI
import AppKit
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

    enum ViewMode: String, CaseIterable, Identifiable {
        case preview = "Preview"
        case source = "Source"
        var id: Self { self }
    }

    private static let log = Logger(subsystem: "app.rhea.mac", category: "markdown")

    var body: some View {
        VStack(spacing: 0) {
            modeBar
            Divider()

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
                        onReadFromOffset: handleReadFromOffset
                    )
                case .source:
                    SourceTextView(text: rawSource)
                }
            }
        }
        .task(id: url) {
            await load()
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
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

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
            rawSource = raw
            Self.log.info("read \(raw.count) chars")

            let parseStart = ContinuousClock.now
            let attributed = MarkdownRenderer.render(raw)
            Self.log.info("rendered markdown in \(ContinuousClock.now - parseStart, privacy: .public)")

            rendered = attributed
            loadFailed = false

            let segmentStart = ContinuousClock.now
            let plain = attributed.string
            let block = DocumentBlock(text: plain, pageIndex: 0, offsetInPage: 0)
            let parsed = await SentenceSegmenter.segment([block])
            let merged = Self.coalesceTableRows(parsed, in: attributed)
            Self.log.info("segmented \(parsed.count) → \(merged.count) sentences in \(ContinuousClock.now - segmentStart, privacy: .public)")

            sentences = merged
            player.load(merged)

            Self.log.info("TOTAL md load \(ContinuousClock.now - started, privacy: .public)")
        } catch {
            Self.log.error("failed to read \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            rawSource = ""
            rendered = NSAttributedString()
            sentences = []
            loadFailed = true
            player.load([])
        }
    }

    /// Collapse sentences that fall inside the same rendered table row
    /// into a single sentence. The renderer tags every character in a
    /// row with `.rheaTableRowID`; we walk the segmentation output,
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
                    .rheaTableRowID,
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
                        .rheaTableRowID,
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
                .foregroundStyle(Color.rheaAccent)
            Text("Couldn't read \(url.lastPathComponent).")
                .font(RheaFont.serif(18))
                .foregroundStyle(.primary)
            Text("Drop another file to try again.")
                .font(RheaFont.ui(13))
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
    static let rheaTableRowID = NSAttributedString.Key("rheaTableRowID")
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
enum MarkdownRenderer {
    static func render(_ markdown: String) -> NSAttributedString {
        let theme = Theme()

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

        for run in attributed.runs {
            let runRange = run.range
            let runText = String(attributed[runRange].characters)
            guard !runText.isEmpty else { continue }

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

        return result
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
                    .rheaTableRowID, value: rowID, range: fullRange
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

        init() {
            let bodyBase = NSFont(name: "New York", size: 16) ?? NSFont.systemFont(ofSize: 16)
            let manager = NSFontManager.shared
            self.body = bodyBase
            self.bodyBold = manager.convert(bodyBase, toHaveTrait: .boldFontMask)
            self.bodyItalic = manager.convert(bodyBase, toHaveTrait: .italicFontMask)
            self.bodyBoldItalic = manager.convert(bodyBold, toHaveTrait: .italicFontMask)
            self.mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            self.monoBold = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)

            let h1Base = NSFont(name: "New York", size: 28) ?? NSFont.systemFont(ofSize: 28)
            let h2Base = NSFont(name: "New York", size: 22) ?? NSFont.systemFont(ofSize: 22)
            let h3Base = NSFont(name: "New York", size: 18) ?? NSFont.systemFont(ofSize: 18)
            let h4Base = NSFont(name: "New York", size: 16) ?? NSFont.systemFont(ofSize: 16)
            self.h1 = manager.convert(h1Base, toHaveTrait: .boldFontMask)
            self.h2 = manager.convert(h2Base, toHaveTrait: .boldFontMask)
            self.h3 = manager.convert(h3Base, toHaveTrait: .boldFontMask)
            self.h4 = manager.convert(h4Base, toHaveTrait: .boldFontMask)

            let para = NSMutableParagraphStyle()
            para.lineHeightMultiple = 1.25
            para.paragraphSpacing = 6

            self.bodyAttributes = [
                .font: bodyBase,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: para,
            ]
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
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        makeReadOnlyTextScrollView(onReadFromOffset: onReadFromOffset)
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? ClickableReaderTextView,
              let storage = tv.textStorage else { return }

        tv.onReadFromOffset = onReadFromOffset

        let identity = ObjectIdentifier(attributed)
        if context.coordinator.lastAttributedIdentity != identity {
            storage.setAttributedString(attributed)
            context.coordinator.lastAttributedIdentity = identity
            context.coordinator.lastSentenceRange = nil
            context.coordinator.lastSubRange = nil
            context.coordinator.lastScrolledSentenceIndex = nil
        }

        applyHighlightIncremental(
            to: tv,
            storage: storage,
            coordinator: context.coordinator,
            sentence: activeSentence,
            spokenSubRange: spokenSubRange
        )
    }
}

private struct SourceTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        // Source view: plain NSTextView, no click-to-start — the
        // raw markdown source offsets don't line up with rendered
        // sentence offsets, so a click there wouldn't map cleanly.
        let scroll = makeReadOnlyTextScrollView(onReadFromOffset: nil)
        if let tv = scroll.documentView as? NSTextView {
            tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            tv.textColor = NSColor.labelColor
            tv.string = text
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text {
            tv.string = text
        }
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
    scroll.backgroundColor = NSColor(Color.rheaSurface)

    let textView: NSTextView
    if let onReadFromOffset {
        let clickable = ClickableReaderTextView()
        clickable.onReadFromOffset = onReadFromOffset
        textView = clickable
    } else {
        textView = NSTextView()
    }
    textView.isEditable = false
    textView.isSelectable = true
    textView.isRichText = true
    textView.backgroundColor = NSColor(Color.rheaSurface)
    textView.drawsBackground = true
    textView.textContainerInset = NSSize(width: 32, height: 24)
    textView.autoresizingMask = [.width]
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.containerSize = NSSize(
        width: 0, height: CGFloat.greatestFiniteMagnitude
    )

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

    let soft = NSColor(Color.rheaAccent).withAlphaComponent(0.25)
    storage.addAttribute(.backgroundColor, value: soft, range: sentenceRange)
    coordinator.lastSentenceRange = sentenceRange

    if let sub = spokenSubRange {
        let subOrigin = sentence.offsetInBlock + sub.location
        let subRange = NSRange(location: subOrigin, length: sub.length)
        if NSMaxRange(subRange) <= storage.length {
            let bright = NSColor(Color.rheaAccent).withAlphaComponent(0.55)
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
