import Foundation

/// A single extracted block of text from a document, in source order.
///
/// `offsetInPage` is the UTF-16 offset of this block within its
/// owning page's `PDFPage.string` — recorded during extraction so
/// the M1.6 highlight layer can resolve a sentence to a
/// `PDFSelection` via `PDFPage.selection(for: NSRange)` in O(1)
/// instead of paying a per-state-change `PDFDocument.findString`
/// scan. For non-PDF inputs (markdown, clipboard) `offsetInPage` is
/// zero — there's only one virtual page.
///
/// For M1.3 every block is treated as a paragraph; a `kind` enum
/// (heading vs paragraph) lands in M4.1 when audiobook chapter
/// markers need it. Keeping the type minimal now avoids paying for
/// a distinction we can't yet act on.
struct DocumentBlock: Equatable, Hashable, Sendable {
    let text: String
    let pageIndex: Int
    let offsetInPage: Int
}
