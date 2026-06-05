import XCTest
@testable import ReadAloudTTS

final class SelectionReaderTests: XCTestCase {

    func test_selectionCaptured_whenChangeCountAdvancedAndCopyNonEmpty() {
        let outcome = SelectionReader.decide(
            beforeChangeCount: 5,
            afterChangeCount: 6,
            copiedString: "  hello world  ",
            originalClipboard: "old clip",
            restoreEnabled: true
        )
        XCTAssertEqual(outcome.text, "hello world")
        XCTAssertEqual(outcome.source, .selection)
        XCTAssertTrue(outcome.shouldRestoreClipboard)
        XCTAssertFalse(outcome.selectionBlocked)
    }

    func test_restoreFlagFollowsSetting() {
        let outcome = SelectionReader.decide(
            beforeChangeCount: 1,
            afterChangeCount: 2,
            copiedString: "x",
            originalClipboard: nil,
            restoreEnabled: false
        )
        XCTAssertEqual(outcome.source, .selection)
        XCTAssertFalse(outcome.shouldRestoreClipboard)
    }

    func test_fallsBackToClipboard_whenChangeCountUnchanged() {
        // Synthetic copy never registered (blocked or nothing selected
        // in a no-op-on-empty app). The stale `copiedString` must be
        // ignored in favour of the real clipboard.
        let outcome = SelectionReader.decide(
            beforeChangeCount: 9,
            afterChangeCount: 9,
            copiedString: "stale selection text",
            originalClipboard: "the clipboard",
            restoreEnabled: true
        )
        XCTAssertEqual(outcome.text, "the clipboard")
        XCTAssertEqual(outcome.source, .clipboard)
        XCTAssertFalse(outcome.shouldRestoreClipboard)
        XCTAssertTrue(outcome.selectionBlocked)
    }

    func test_fallsBackToClipboard_whenSelectionEmpty() {
        // Cmd+C registered (advanced) but the selection was whitespace.
        // Treated as an empty selection, not a permission block.
        let outcome = SelectionReader.decide(
            beforeChangeCount: 2,
            afterChangeCount: 3,
            copiedString: "   \n ",
            originalClipboard: "clip",
            restoreEnabled: true
        )
        XCTAssertEqual(outcome.text, "clip")
        XCTAssertEqual(outcome.source, .clipboard)
        XCTAssertFalse(outcome.selectionBlocked)
    }

    func test_nothingToRead_whenBothEmpty() {
        let outcome = SelectionReader.decide(
            beforeChangeCount: 0,
            afterChangeCount: 0,
            copiedString: nil,
            originalClipboard: "   ",
            restoreEnabled: true
        )
        XCTAssertNil(outcome.text)
        XCTAssertNil(outcome.source)
        XCTAssertFalse(outcome.shouldRestoreClipboard)
        XCTAssertTrue(outcome.selectionBlocked)
    }
}
