import XCTest
@testable import Rhea

final class SentenceSegmenterTests: XCTestCase {

    func test_empty_inputProducesNoSentences() {
        XCTAssertEqual(SentenceSegmenter.segmentSync([]), [])
    }

    func test_emptyBlock_producesNoSentences() {
        let blocks = [DocumentBlock(text: "", pageIndex: 0, offsetInPage: 0)]
        XCTAssertEqual(SentenceSegmenter.segmentSync(blocks), [])
    }

    func test_whitespaceOnlyBlock_producesNoSentences() {
        let blocks = [DocumentBlock(text: "   \n  \n", pageIndex: 0, offsetInPage: 0)]
        XCTAssertEqual(SentenceSegmenter.segmentSync(blocks), [])
    }

    func test_english_threeSentencesInOneBlock() {
        let blocks = [
            DocumentBlock(text: "Hello there. How are you? Fine, thanks.", pageIndex: 0, offsetInPage: 0)
        ]
        let sentences = SentenceSegmenter.segmentSync(blocks)
        XCTAssertEqual(sentences.map(\.text), [
            "Hello there.",
            "How are you?",
            "Fine, thanks."
        ])
        XCTAssertTrue(sentences.allSatisfy { $0.blockIndex == 0 })
    }

    func test_chinese_twoSentencesInOneBlock() {
        let blocks = [
            DocumentBlock(text: "你好。今天天气很好。", pageIndex: 0, offsetInPage: 0)
        ]
        let sentences = SentenceSegmenter.segmentSync(blocks)
        XCTAssertEqual(sentences.count, 2)
        XCTAssertEqual(sentences[0].text, "你好。")
        XCTAssertEqual(sentences[1].text, "今天天气很好。")
    }

    func test_multipleBlocks_carryCorrectBlockIndex() {
        let blocks = [
            DocumentBlock(text: "First block, one sentence.", pageIndex: 0, offsetInPage: 0),
            DocumentBlock(text: "Second block here. And a second sentence.", pageIndex: 1, offsetInPage: 0),
        ]
        let sentences = SentenceSegmenter.segmentSync(blocks)
        XCTAssertEqual(sentences.count, 3)
        XCTAssertEqual(sentences.map(\.blockIndex), [0, 1, 1])
    }

    func test_offsets_roundTripToOriginalText() {
        let text = "Alpha sentence. Beta sentence! Gamma?"
        let blocks = [DocumentBlock(text: text, pageIndex: 0, offsetInPage: 0)]
        let sentences = SentenceSegmenter.segmentSync(blocks)
        let ns = text as NSString

        for sentence in sentences {
            let slice = ns.substring(with: NSRange(
                location: sentence.offsetInBlock,
                length: sentence.lengthInBlock
            ))
            let trimmed = slice.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(trimmed, sentence.text)
        }
    }

    func test_chineseOffsets_roundTripInUTF16() {
        // 你好 is 2 UTF-16 code units, 。 is 1, so sentence offsets
        // in UTF-16 units must reconstruct the same substring.
        let text = "你好。今天天气很好。"
        let blocks = [DocumentBlock(text: text, pageIndex: 0, offsetInPage: 0)]
        let sentences = SentenceSegmenter.segmentSync(blocks)
        let ns = text as NSString

        XCTAssertEqual(sentences.count, 2)
        for sentence in sentences {
            let slice = ns.substring(with: NSRange(
                location: sentence.offsetInBlock,
                length: sentence.lengthInBlock
            ))
            XCTAssertEqual(slice.trimmingCharacters(in: .whitespacesAndNewlines), sentence.text)
        }
    }
}
