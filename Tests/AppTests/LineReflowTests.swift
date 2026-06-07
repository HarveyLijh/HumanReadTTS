import XCTest
@testable import ReadAloudTTS

final class LineReflowTests: XCTestCase {

    func test_singleNewline_becomesSpace() {
        XCTAssertEqual(LineReflow.reflow("alpha\nbeta"), "alpha beta")
    }

    func test_crlf_becomesTwoSpaces_lengthPreserved() {
        // A `\r\n` pair is one logical wrap; each character is replaced
        // in place so the length is preserved (two spaces).
        XCTAssertEqual(LineReflow.reflow("alpha\r\nbeta"), "alpha  beta")
    }

    func test_loneCarriageReturn_becomesSpace() {
        XCTAssertEqual(LineReflow.reflow("alpha\rbeta"), "alpha beta")
    }

    func test_blankLineRun_isPreserved() {
        XCTAssertEqual(LineReflow.reflow("para one.\n\npara two."), "para one.\n\npara two.")
    }

    func test_tripleNewline_isPreserved() {
        XCTAssertEqual(LineReflow.reflow("a\n\n\nb"), "a\n\n\nb")
    }

    func test_crlfBlankLine_isPreserved() {
        // Two logical breaks (`\r\n\r\n`) is a paragraph separator.
        XCTAssertEqual(LineReflow.reflow("a\r\n\r\nb"), "a\r\n\r\nb")
    }

    func test_noLineBreaks_isUnchanged() {
        XCTAssertEqual(LineReflow.reflow("just words here"), "just words here")
    }

    func test_emptyString_isUnchanged() {
        XCTAssertEqual(LineReflow.reflow(""), "")
    }

    func test_multiLineParagraph_collapsesToOneFlowingLine() {
        let wrapped = "Learning happens wherever people confront problems they do not yet know how to solve, and it\nhappens at least as often outside classrooms as within them."
        XCTAssertEqual(
            LineReflow.reflow(wrapped),
            "Learning happens wherever people confront problems they do not yet know how to solve, and it happens at least as often outside classrooms as within them."
        )
    }

    // The length invariant is what lets the highlight layer reuse offsets
    // computed on the reflowed copy against the original text.
    func test_lengthIsPreserved_acrossLineBreakKinds() {
        let inputs = [
            "alpha\nbeta",
            "alpha\r\nbeta",
            "para one.\n\npara two.",
            "你好\n世界。",
            "a\rb\nc\r\nd",
        ]
        for input in inputs {
            XCTAssertEqual(
                (LineReflow.reflow(input) as NSString).length,
                (input as NSString).length,
                "length changed for [\(input)]"
            )
        }
    }
}
