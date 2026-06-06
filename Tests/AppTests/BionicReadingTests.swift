import XCTest
import AppKit
@testable import ReadAloudTTS

final class BionicReadingTests: XCTestCase {

    func test_boldPrefixLength_scalesWithWordLength() {
        XCTAssertEqual(BionicReading.boldPrefixLength(wordLength: 0), 0)
        XCTAssertEqual(BionicReading.boldPrefixLength(wordLength: 1), 1)
        XCTAssertEqual(BionicReading.boldPrefixLength(wordLength: 3), 1)
        XCTAssertEqual(BionicReading.boldPrefixLength(wordLength: 4), 2)
        XCTAssertEqual(BionicReading.boldPrefixLength(wordLength: 6), 2)
        XCTAssertEqual(BionicReading.boldPrefixLength(wordLength: 7), 3)   // round(2.8)
        XCTAssertEqual(BionicReading.boldPrefixLength(wordLength: 10), 4)  // round(4.0)
        XCTAssertEqual(BionicReading.boldPrefixLength(wordLength: 12), 5)  // round(4.8)
        XCTAssertEqual(BionicReading.boldPrefixLength(wordLength: 100), 5) // capped
    }

    func test_emphasize_boldsLeadingCharactersOfEachWord() {
        let regular = NSFont.systemFont(ofSize: 14)
        let storage = NSMutableAttributedString(
            string: "Hello world",
            attributes: [.font: regular]
        )
        BionicReading.emphasize(storage)

        // "Hello" (len 5) -> first 2 bold, rest not.
        XCTAssertTrue(isBold(storage, at: 0))
        XCTAssertTrue(isBold(storage, at: 1))
        XCTAssertFalse(isBold(storage, at: 2))
        XCTAssertFalse(isBold(storage, at: 4))
        // The space is untouched.
        XCTAssertFalse(isBold(storage, at: 5))
        // "world" (len 5) -> first 2 bold.
        XCTAssertTrue(isBold(storage, at: 6))
        XCTAssertTrue(isBold(storage, at: 7))
        XCTAssertFalse(isBold(storage, at: 8))
    }

    func test_emphasize_preservesCharactersAndLength() {
        let storage = NSMutableAttributedString(
            string: "The quick brown fox.",
            attributes: [.font: NSFont.systemFont(ofSize: 13)]
        )
        BionicReading.emphasize(storage)
        XCTAssertEqual(storage.string, "The quick brown fox.",
                       "emphasis must not change characters — only fonts")
    }

    func test_emphasize_emptyString_isNoop() {
        let storage = NSMutableAttributedString(string: "")
        BionicReading.emphasize(storage) // must not crash
        XCTAssertEqual(storage.length, 0)
    }

    private func isBold(_ storage: NSAttributedString, at index: Int) -> Bool {
        guard let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
        else { return false }
        return font.fontDescriptor.symbolicTraits.contains(.bold)
    }
}
