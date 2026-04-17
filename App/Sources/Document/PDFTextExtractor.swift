import Foundation
import PDFKit

/// Walks a `PDFDocument` page by page, splits each page's text on
/// blank lines, and returns the resulting blocks in source order.
///
/// This is the day-one extraction path per ADR-004: zero
/// dependencies, zero subprocesses, fully sandbox-safe. Marker (and
/// optionally MinerU for Chinese-heavy PDFs) lands in Month 3 as an
/// opt-in enhancer for documents PDFKit handles poorly.
enum PDFTextExtractor {
    /// Run the extraction on a detached task so large PDFs don't
    /// block the main actor. `PDFDocument` is not formally Sendable
    /// but is safe when the reference is transferred uniquely; see
    /// the extension in `PDFDocumentLoader.swift`.
    static func extract(_ document: PDFDocument) async -> [DocumentBlock] {
        await Task.detached(priority: .userInitiated) {
            extractSync(document)
        }.value
    }

    static func extractSync(_ document: PDFDocument) -> [DocumentBlock] {
        var blocks: [DocumentBlock] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex),
                  let raw = page.string, !raw.isEmpty else {
                continue
            }
            for block in splitOnBlankLines(raw) {
                blocks.append(DocumentBlock(text: block, pageIndex: pageIndex))
            }
        }
        return blocks
    }

    /// Splits a string on runs of two-or-more consecutive line breaks
    /// (i.e. blank lines). Each emitted block is trimmed of
    /// surrounding whitespace; empty blocks are dropped. Handles
    /// both `\n` and `\r\n` line endings.
    static func splitOnBlankLines(_ text: String) -> [String] {
        var blocks: [String] = []
        var current = ""
        var consecutiveNewlines = 0

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { blocks.append(trimmed) }
            current.removeAll(keepingCapacity: true)
        }

        for ch in text {
            if ch == "\n" || ch == "\r" {
                consecutiveNewlines += 1
                if consecutiveNewlines == 2 {
                    flush()
                } else if consecutiveNewlines == 1 {
                    current.append(ch)
                }
                // 3+ consecutive: already flushed; just keep skipping.
            } else {
                consecutiveNewlines = 0
                current.append(ch)
            }
        }
        flush()
        return blocks
    }
}
