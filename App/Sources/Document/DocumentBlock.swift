import Foundation

/// A single extracted block of text from a document, in source order.
///
/// For M1.3 every block is treated as a paragraph; a `kind` enum
/// (heading vs paragraph) lands in M4.1 when audiobook chapter
/// markers need it. Keeping the type minimal now avoids paying for a
/// distinction we can't yet act on.
struct DocumentBlock: Equatable, Hashable, Sendable {
    /// The trimmed text of the block. Newlines inside the text are
    /// preserved so the downstream sentence segmenter (M1.4) can decide
    /// whether to treat them as sentence boundaries.
    let text: String

    /// Zero-based index of the page this block was extracted from.
    let pageIndex: Int
}
