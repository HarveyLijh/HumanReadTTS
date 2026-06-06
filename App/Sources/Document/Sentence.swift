import Foundation

/// A single sentence extracted from a `DocumentBlock`, with enough
/// source metadata for later layers to locate it:
///
/// - `blockIndex` is the index into the `[DocumentBlock]` array that
///   produced this sentence, so the owning page is one dereference
///   away via `blocks[blockIndex].pageIndex`.
/// - `offsetInBlock` and `lengthInBlock` are UTF-16 units (NSString-
///   compatible), because every downstream consumer — `NLTokenizer`,
///   `NSRange`, `PDFDocument.findString`, `AVSpeechSynthesizer`
///   callbacks — speaks UTF-16. Using `String.Index` here would force
///   translation at every boundary and isn't `Sendable`.
struct Sentence: Equatable, Hashable, Sendable {
    let text: String
    let blockIndex: Int
    let offsetInBlock: Int
    let lengthInBlock: Int
    /// BCP-47 language code detected for this sentence (e.g. `"en"`,
    /// `"zh-Hans"`), or nil when detection was skipped or inconclusive.
    /// Populated by `SentenceSegmenter`; bilingual features read it to
    /// route voices and translation without re-detecting. Optional with
    /// an init default so callers that don't care can omit it.
    let language: String?

    init(
        text: String,
        blockIndex: Int,
        offsetInBlock: Int,
        lengthInBlock: Int,
        language: String? = nil
    ) {
        self.text = text
        self.blockIndex = blockIndex
        self.offsetInBlock = offsetInBlock
        self.lengthInBlock = lengthInBlock
        self.language = language
    }
}
