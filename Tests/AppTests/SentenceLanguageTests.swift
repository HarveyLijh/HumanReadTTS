import XCTest
@testable import ReadAloudTTS

final class SentenceLanguageTests: XCTestCase {

    func test_detectLanguage_english() {
        let lang = SentenceSegmenter.detectLanguage("This is clearly an English sentence about reading.")
        XCTAssertEqual(lang, "en")
    }

    func test_detectLanguage_chinese() {
        let lang = SentenceSegmenter.detectLanguage("这是一个用于测试的中文句子。")
        XCTAssertTrue(lang?.hasPrefix("zh") ?? false,
                      "expected a Chinese tag, got \(lang ?? "nil")")
    }

    func test_detectLanguage_skipsVeryShortText() {
        XCTAssertNil(SentenceSegmenter.detectLanguage("Hi"))
        XCTAssertNil(SentenceSegmenter.detectLanguage("ok"))
    }

    func test_segmentSync_tagsSentencesWithLanguage() {
        let block = DocumentBlock(
            text: "The reader follows along. Each sentence is highlighted.",
            pageIndex: 0,
            offsetInPage: 0
        )
        let sentences = SentenceSegmenter.segmentSync([block])
        XCTAssertFalse(sentences.isEmpty)
        XCTAssertTrue(sentences.allSatisfy { $0.language == "en" },
                      "English block sentences should all be tagged en")
    }

    func test_sentenceInit_defaultsLanguageToNil() {
        // Back-compat: existing call sites omit the language argument.
        let s = Sentence(text: "x", blockIndex: 0, offsetInBlock: 0, lengthInBlock: 1)
        XCTAssertNil(s.language)
    }

    func test_sentenceLanguage_participatesInEquality() {
        let a = Sentence(text: "x", blockIndex: 0, offsetInBlock: 0, lengthInBlock: 1, language: "en")
        let b = Sentence(text: "x", blockIndex: 0, offsetInBlock: 0, lengthInBlock: 1, language: "zh")
        let c = Sentence(text: "x", blockIndex: 0, offsetInBlock: 0, lengthInBlock: 1, language: "en")
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a, c)
    }
}
