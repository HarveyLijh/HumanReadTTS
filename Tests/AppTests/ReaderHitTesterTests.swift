import XCTest
@testable import Rhea

final class ReaderHitTesterTests: XCTestCase {
    private func sentence(
        offset: Int, length: Int, block: Int = 0
    ) -> Sentence {
        Sentence(
            text: String(repeating: "x", count: length),
            blockIndex: block,
            offsetInBlock: offset,
            lengthInBlock: length
        )
    }

    // MARK: single-block (Markdown / EPUB)

    func testReturnsNilForEmptyQueue() {
        XCTAssertNil(ReaderHitTester.sentenceIndex(forOffset: 0, in: []))
    }

    func testFindsFirstSentence() {
        let sentences = [
            sentence(offset: 0, length: 10),
            sentence(offset: 10, length: 15),
            sentence(offset: 25, length: 20),
        ]
        XCTAssertEqual(ReaderHitTester.sentenceIndex(forOffset: 0, in: sentences), 0)
        XCTAssertEqual(ReaderHitTester.sentenceIndex(forOffset: 5, in: sentences), 0)
        XCTAssertEqual(ReaderHitTester.sentenceIndex(forOffset: 9, in: sentences), 0)
    }

    func testFindsMiddleSentence() {
        let sentences = [
            sentence(offset: 0, length: 10),
            sentence(offset: 10, length: 15),
            sentence(offset: 25, length: 20),
        ]
        XCTAssertEqual(ReaderHitTester.sentenceIndex(forOffset: 10, in: sentences), 1)
        XCTAssertEqual(ReaderHitTester.sentenceIndex(forOffset: 20, in: sentences), 1)
    }

    func testFindsLastSentence() {
        let sentences = [
            sentence(offset: 0, length: 10),
            sentence(offset: 10, length: 15),
            sentence(offset: 25, length: 20),
        ]
        XCTAssertEqual(ReaderHitTester.sentenceIndex(forOffset: 25, in: sentences), 2)
        XCTAssertEqual(ReaderHitTester.sentenceIndex(forOffset: 44, in: sentences), 2)
    }

    func testReturnsNilForGapBetweenSentences() {
        // Sentence 0 ends at offset 10, sentence 1 starts at 15 (a gap
        // the segmenter dropped — e.g. "\n\n" block separator).
        let sentences = [
            sentence(offset: 0, length: 10),
            sentence(offset: 15, length: 10),
        ]
        XCTAssertNil(ReaderHitTester.sentenceIndex(forOffset: 12, in: sentences))
    }

    func testReturnsNilBeyondLastSentence() {
        let sentences = [sentence(offset: 0, length: 10)]
        XCTAssertNil(ReaderHitTester.sentenceIndex(forOffset: 100, in: sentences))
    }

    // MARK: multi-page (PDF)

    func testFindsSentenceOnCorrectPage() {
        let blocks = [
            DocumentBlock(text: "p0", pageIndex: 0, offsetInPage: 0),
            DocumentBlock(text: "p1", pageIndex: 1, offsetInPage: 0),
        ]
        let sentences = [
            Sentence(text: "x", blockIndex: 0, offsetInBlock: 0, lengthInBlock: 50),
            Sentence(text: "y", blockIndex: 0, offsetInBlock: 50, lengthInBlock: 40),
            Sentence(text: "z", blockIndex: 1, offsetInBlock: 0, lengthInBlock: 60),
        ]
        XCTAssertEqual(
            ReaderHitTester.sentenceIndex(
                forPageOffset: 10, pageIndex: 0,
                sentences: sentences, blocks: blocks
            ), 0
        )
        XCTAssertEqual(
            ReaderHitTester.sentenceIndex(
                forPageOffset: 60, pageIndex: 0,
                sentences: sentences, blocks: blocks
            ), 1
        )
        XCTAssertEqual(
            ReaderHitTester.sentenceIndex(
                forPageOffset: 10, pageIndex: 1,
                sentences: sentences, blocks: blocks
            ), 2
        )
    }

    func testReturnsNilWhenClickInEmptyPage() {
        let blocks = [
            DocumentBlock(text: "p0", pageIndex: 0, offsetInPage: 0),
        ]
        let sentences = [
            Sentence(text: "x", blockIndex: 0, offsetInBlock: 0, lengthInBlock: 10),
        ]
        // Page 1 has no sentences — returns nil.
        XCTAssertNil(
            ReaderHitTester.sentenceIndex(
                forPageOffset: 0, pageIndex: 1,
                sentences: sentences, blocks: blocks
            )
        )
    }
}
