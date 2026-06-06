import XCTest
@testable import ReadAloudTTS

final class WordRangeResolverTests: XCTestCase {

    func test_word_atLatinWordInterior() {
        // "The quick brown fox" — index 5 is inside "quick" (4..<9).
        XCTAssertEqual(WordRangeResolver.word(in: "The quick brown fox", at: 5), "quick")
    }

    func test_word_atFirstAndLastWord() {
        let text = "The quick brown fox"
        XCTAssertEqual(WordRangeResolver.word(in: text, at: 0), "The")
        XCTAssertEqual(WordRangeResolver.word(in: text, at: 16), "fox")
    }

    func test_word_onSpace_returnsNil() {
        // Index 3 is the space between "The" and "quick".
        XCTAssertNil(WordRangeResolver.word(in: "The quick brown fox", at: 3))
    }

    func test_word_onPunctuation_returnsNil() {
        // "Hello, world" — index 5 is the comma.
        XCTAssertNil(WordRangeResolver.word(in: "Hello, world", at: 5))
        XCTAssertEqual(WordRangeResolver.word(in: "Hello, world", at: 0), "Hello")
    }

    func test_word_outOfBounds_returnsNil() {
        XCTAssertNil(WordRangeResolver.word(in: "hi", at: -1))
        XCTAssertNil(WordRangeResolver.word(in: "hi", at: 2))
        XCTAssertNil(WordRangeResolver.word(in: "", at: 0))
    }

    func test_wordRange_coversIndexAndMatchesSubstring() {
        let text = "The quick brown fox"
        let range = WordRangeResolver.wordRange(in: text, at: 12)! // inside "brown"
        XCTAssertTrue(range.location <= 12 && 12 < NSMaxRange(range))
        XCTAssertEqual((text as NSString).substring(with: range), "brown")
    }

    func test_sentence_returnsEnclosingSentenceTrimmed() {
        let text = "I like apples. She reads books. We walk home."
        // Index 20 is inside "reads" of the middle sentence.
        XCTAssertEqual(WordRangeResolver.sentence(in: text, at: 20), "She reads books.")
    }

    func test_sentence_firstAndLast() {
        let text = "Hello world. Goodbye now."
        XCTAssertEqual(WordRangeResolver.sentence(in: text, at: 0), "Hello world.")
        XCTAssertEqual(WordRangeResolver.sentence(in: text, at: 20), "Goodbye now.")
    }

    func test_sentence_outOfBounds_returnsNil() {
        XCTAssertNil(WordRangeResolver.sentence(in: "hi", at: -1))
        XCTAssertNil(WordRangeResolver.sentence(in: "hi", at: 5))
        XCTAssertNil(WordRangeResolver.sentence(in: "", at: 0))
    }

    func test_sentence_chineseContext() {
        let text = "他正在过马路。请小心。"
        // The first clause's terminator (。) lands mid-string; an index in
        // the first clause returns that clause as context.
        let sentence = WordRangeResolver.sentence(in: text, at: 2)
        XCTAssertNotNil(sentence)
        XCTAssertTrue(sentence!.contains("过马路"))
    }

    func test_word_chineseSegmentsIntoWordNotGlyph() {
        // "我喜欢苹果" — clicking a character returns its whole word, which
        // includes the pointed-at character and is at least one char.
        let text = "我喜欢苹果"
        for index in 0..<(text as NSString).length {
            let word = WordRangeResolver.word(in: text, at: index)
            XCTAssertNotNil(word, "char at \(index) should resolve to a word")
            let char = (text as NSString).substring(with: NSRange(location: index, length: 1))
            XCTAssertTrue(word!.contains(char),
                          "word \(word!) should contain pointed char \(char)")
        }
    }
}
