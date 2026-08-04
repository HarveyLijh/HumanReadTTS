import XCTest
import CoreGraphics
@testable import HumanReadTTS

final class ReadingOrderTests: XCTestCase {

    private func box(_ text: String, _ x: CGFloat, _ y: CGFloat,
                     _ w: CGFloat = 0.4, _ h: CGFloat = 0.06) -> TextBox {
        TextBox(text: text, rect: CGRect(x: x, y: y, width: w, height: h))
    }

    private func order(_ boxes: [TextBox]) -> [String] {
        ReadingOrder.sort(boxes).map(\.text)
    }

    func test_singleColumn_readsTopToBottom() {
        let boxes = [
            box("L3", 0.1, 0.5, 0.8),
            box("L1", 0.1, 0.1, 0.8),
            box("L2", 0.1, 0.3, 0.8),
        ]
        XCTAssertEqual(order(boxes), ["L1", "L2", "L3"])
    }

    func test_twoColumns_readEachColumnFullyBeforeMovingRight() {
        let boxes = [
            box("B2", 0.55, 0.3),
            box("A1", 0.05, 0.1),
            box("B1", 0.55, 0.1),
            box("A2", 0.05, 0.3),
        ]
        XCTAssertEqual(order(boxes), ["A1", "A2", "B1", "B2"])
    }

    func test_singleLine_readsLeftToRight() {
        let boxes = [
            box("W3", 0.5, 0.1, 0.1),
            box("W1", 0.1, 0.1, 0.1),
            box("W2", 0.3, 0.1, 0.1),
        ]
        XCTAssertEqual(order(boxes), ["W1", "W2", "W3"])
    }

    func test_titleOverTwoColumns_titleFirstThenColumns() {
        let boxes = [
            box("T", 0.1, 0.05, 0.8),
            box("A1", 0.05, 0.2),
            box("A2", 0.05, 0.4),
            box("B1", 0.55, 0.2),
            box("B2", 0.55, 0.4),
        ]
        XCTAssertEqual(order(boxes), ["T", "A1", "A2", "B1", "B2"])
    }

    func test_emptyAndSingle_areReturnedAsIs() {
        XCTAssertEqual(ReadingOrder.sort([]).count, 0)
        let one = [box("only", 0.3, 0.3)]
        XCTAssertEqual(order(one), ["only"])
    }

    func test_orderedText_joinsWithNewlines() {
        let boxes = [box("second", 0.1, 0.4, 0.8), box("first", 0.1, 0.1, 0.8)]
        XCTAssertEqual(ReadingOrder.orderedText(boxes), "first\nsecond")
    }
}
