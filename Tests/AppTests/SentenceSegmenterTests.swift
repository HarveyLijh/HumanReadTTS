import XCTest
@testable import HumanReadTTS

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

    // MARK: reflowLineWraps

    /// A PDF-style block where one sentence is hard-wrapped across four
    /// visual lines. Without reflow `NLTokenizer` splits on every `\n`.
    private static let wrappedBlock = DocumentBlock(
        text: "Learning happens wherever people confront problems they do not yet know how to solve, and it\nhappens at least as often outside classrooms as within them: in the puzzle a player retries until it\nclicks, in the game whose rules must be mastered before one can advance, in any unfamiliar task\napproached by trial and error. What most determines whether a person learns or disengages.",
        pageIndex: 0,
        offsetInPage: 0
    )

    func test_reflow_joinsWrappedLinesIntoRealSentences() {
        let sentences = SentenceSegmenter.segmentSync([Self.wrappedBlock], reflowLineWraps: true)
        XCTAssertEqual(sentences.count, 2)
        XCTAssertEqual(sentences.first?.text.hasSuffix("trial and error."), true)
        XCTAssertEqual(sentences.last?.text.hasPrefix("What most determines"), true)
    }

    func test_reflow_sentencesHaveNoInternalNewlines() {
        let sentences = SentenceSegmenter.segmentSync([Self.wrappedBlock], reflowLineWraps: true)
        XCTAssertTrue(sentences.allSatisfy { !$0.text.contains("\n") })
    }

    func test_default_keepsPerLineFragmentation() {
        // reflowLineWraps defaults to false: behavior is unchanged, so
        // the hard-wrapped block still fragments per visual line.
        let sentences = SentenceSegmenter.segmentSync([Self.wrappedBlock])
        XCTAssertGreaterThan(sentences.count, 2)
    }

    func test_reflow_offsetsAddressLengthIdenticalReflowedText() {
        // The recorded offsets are computed on the reflowed copy. Because
        // reflow is length-preserving they also index the original block
        // text, which is what the PDF highlight layer relies on.
        let sentences = SentenceSegmenter.segmentSync([Self.wrappedBlock], reflowLineWraps: true)
        let reflowed = LineReflow.reflow(Self.wrappedBlock.text) as NSString
        XCTAssertEqual(reflowed.length, (Self.wrappedBlock.text as NSString).length)
        for sentence in sentences {
            let slice = reflowed.substring(with: NSRange(
                location: sentence.offsetInBlock,
                length: sentence.lengthInBlock
            )).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(slice, sentence.text)
        }
    }

    func test_reflow_doesNotDisturbSingleLineSegmentation() {
        let blocks = [DocumentBlock(text: "Hello there. How are you? Fine, thanks.", pageIndex: 0, offsetInPage: 0)]
        let sentences = SentenceSegmenter.segmentSync(blocks, reflowLineWraps: true)
        XCTAssertEqual(sentences.map(\.text), ["Hello there.", "How are you?", "Fine, thanks."])
    }

    func test_reflow_preservesParagraphBreakBetweenHeadingAndBody() {
        // A blank line separates a heading from the body; the run of two
        // breaks is preserved so they don't merge into one sentence.
        let blocks = [DocumentBlock(text: "Introduction\n\nThe study began in earnest.", pageIndex: 0, offsetInPage: 0)]
        let sentences = SentenceSegmenter.segmentSync(blocks, reflowLineWraps: true).map(\.text)
        XCTAssertTrue(sentences.contains("Introduction"))
        XCTAssertTrue(sentences.contains("The study began in earnest."))
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
