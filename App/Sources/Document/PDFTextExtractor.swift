import Foundation
import PDFKit

/// Walks a `PDFDocument` page by page, splits each page's text on
/// blank lines, and returns the resulting blocks in source order.
/// Each block records its UTF-16 offset within the source page so
/// the highlight layer (M1.6) can map a sentence to a `PDFSelection`
/// in O(1) without the per-state-change `findString` scan that
/// stalled on large documents.
///
/// This is the day-one extraction path per ADR-004: zero
/// dependencies, zero subprocesses, fully sandbox-safe. Marker
/// (and optionally MinerU for Chinese-heavy PDFs) lands in Month 3
/// as an opt-in enhancer for documents PDFKit handles poorly.
enum PDFTextExtractor {
    static func extract(
        _ document: PDFDocument,
        skipFigureCaptions: Bool = false
    ) async -> [DocumentBlock] {
        await Task.detached(priority: .userInitiated) {
            extractSync(document, skipFigureCaptions: skipFigureCaptions)
        }.value
    }

    static func extractSync(
        _ document: PDFDocument,
        skipFigureCaptions: Bool = false
    ) -> [DocumentBlock] {
        var blocks: [DocumentBlock] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let raw = page.string, !raw.isEmpty else {
                continue
            }
            for (offset, text) in splitOnBlankLines(raw) {
                if skipFigureCaptions, ResearchCleanup.isFigureOrTableBlock(text) {
                    continue
                }
                blocks.append(DocumentBlock(
                    text: text,
                    pageIndex: pageIndex,
                    offsetInPage: offset
                ))
            }
        }
        return blocks
    }

    /// Splits a string on runs of two-or-more consecutive line
    /// breaks (i.e. blank lines). Returns each emitted block paired
    /// with its UTF-16 offset in the source string. Trims
    /// surrounding whitespace from the block text but reports the
    /// offset of the trimmed substring (not the leading whitespace).
    /// Empty blocks are dropped. Handles `\n` and `\r\n`.
    static func splitOnBlankLines(_ text: String) -> [(offset: Int, text: String)] {
        var blocks: [(offset: Int, text: String)] = []
        let ns = text as NSString
        let length = ns.length

        var i = 0
        while i < length {
            // Skip any leading whitespace/newlines, tracking position.
            while i < length, isWhitespaceOrNewline(ns.character(at: i)) {
                i += 1
            }
            guard i < length else { break }

            let blockStart = i
            // Walk until we hit two-or-more consecutive newlines.
            var lastNonWhitespace = i
            while i < length {
                let ch = ns.character(at: i)
                if ch == 0x0A || ch == 0x0D {
                    var newlineRun = 0
                    var j = i
                    while j < length, ns.character(at: j) == 0x0A || ns.character(at: j) == 0x0D {
                        newlineRun += 1
                        j += 1
                    }
                    if newlineRun >= 2 {
                        i = j
                        break
                    }
                    // Single newline counts as part of the block.
                    i = j
                } else {
                    if !isWhitespace(ch) { lastNonWhitespace = i }
                    i += 1
                }
            }

            let blockEnd = lastNonWhitespace + 1
            guard blockEnd > blockStart else { continue }
            let range = NSRange(location: blockStart, length: blockEnd - blockStart)
            let slice = ns.substring(with: range)
            if !slice.isEmpty {
                blocks.append((offset: blockStart, text: slice))
            }
        }
        return blocks
    }

    private static func isWhitespaceOrNewline(_ ch: unichar) -> Bool {
        // Tab, LF, CR, space.
        ch == 0x09 || ch == 0x0A || ch == 0x0D || ch == 0x20
    }

    private static func isWhitespace(_ ch: unichar) -> Bool {
        ch == 0x09 || ch == 0x20
    }
}
