import Foundation
import NaturalLanguage

/// Splits each `DocumentBlock` into an ordered list of `Sentence`s
/// using `NLTokenizer`, the current Apple-recommended sentence
/// tokenizer (replaces the older `NSLinguisticTagger` API).
///
/// Language is detected automatically via `NLTokenizer.setLanguage`
/// inference. Mixed English/Chinese works out of the box — Qwen3-TTS
/// paragraph-level routing in Month 3 will set language explicitly
/// when we already know it.
enum SentenceSegmenter {
    /// Run segmentation on a detached task. Very large documents
    /// still walk quickly (NLTokenizer is native code), but keeping
    /// it off the main actor matches the extractor and keeps the
    /// UI responsive during the `task(id:)` chain.
    static func segment(
        _ blocks: [DocumentBlock],
        reflowLineWraps: Bool = false
    ) async -> [Sentence] {
        await Task.detached(priority: .userInitiated) {
            segmentSync(blocks, reflowLineWraps: reflowLineWraps)
        }.value
    }

    /// - Parameter reflowLineWraps: When true, intra-paragraph line
    ///   wraps in each block are collapsed to spaces (via `LineReflow`)
    ///   before tokenizing, so a sentence that spans several wrapped
    ///   lines is recognized as one sentence instead of one fragment per
    ///   line. Set by callers whose source is segregated by *visual*
    ///   lines (PDF, OCR, text exported from a PDF). Because the reflow
    ///   is length-preserving, the recorded UTF-16 offsets still address
    ///   the original block text, so the highlight layer is unaffected.
    static func segmentSync(
        _ blocks: [DocumentBlock],
        reflowLineWraps: Bool = false
    ) -> [Sentence] {
        var sentences: [Sentence] = []
        let tokenizer = NLTokenizer(unit: .sentence)

        for (blockIndex, block) in blocks.enumerated() {
            // Reflow is length-preserving, so the NSRanges computed below
            // are valid against the original block text too — the
            // highlight layer needs no remapping.
            let text = reflowLineWraps ? LineReflow.reflow(block.text) : block.text
            guard !text.isEmpty else { continue }

            tokenizer.string = text
            let nsText = text as NSString

            tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
                // Convert Swift String.Index range to NSRange for UTF-16
                // offset/length — the unit every downstream consumer uses.
                let nsRange = NSRange(range, in: text)
                let slice = nsText.substring(with: nsRange)
                let trimmed = slice.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return true }

                sentences.append(Sentence(
                    text: trimmed,
                    blockIndex: blockIndex,
                    offsetInBlock: nsRange.location,
                    lengthInBlock: nsRange.length,
                    language: detectLanguage(trimmed)
                ))
                return true
            }
        }

        return sentences
    }

    /// Best-effort BCP-47 language for a sentence. Very short fragments
    /// are skipped (nil) because the recognizer is unreliable on a word
    /// or two, and a wrong tag is worse than none for downstream voice
    /// and translation routing.
    static func detectLanguage(_ text: String) -> String? {
        guard text.count >= 4 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }
}
