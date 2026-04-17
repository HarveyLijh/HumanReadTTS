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
    static func segment(_ blocks: [DocumentBlock]) async -> [Sentence] {
        await Task.detached(priority: .userInitiated) {
            segmentSync(blocks)
        }.value
    }

    static func segmentSync(_ blocks: [DocumentBlock]) -> [Sentence] {
        var sentences: [Sentence] = []
        let tokenizer = NLTokenizer(unit: .sentence)

        for (blockIndex, block) in blocks.enumerated() {
            let text = block.text
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
                    lengthInBlock: nsRange.length
                ))
                return true
            }
        }

        return sentences
    }
}
