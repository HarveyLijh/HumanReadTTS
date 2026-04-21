import XCTest
import AppKit
@testable import Rhea

final class MarkdownRendererTests: XCTestCase {

    // MARK: block separators

    func test_singleParagraph_hasNoSeparator() {
        let rendered = MarkdownRenderer.render("Hello world.")
        XCTAssertEqual(rendered.string, "Hello world.")
    }

    func test_twoParagraphs_areSeparatedByBlankLine() {
        let rendered = MarkdownRenderer.render("First paragraph.\n\nSecond paragraph.")
        // Expect a visible gap between blocks — two newlines.
        XCTAssertTrue(rendered.string.contains("First paragraph."))
        XCTAssertTrue(rendered.string.contains("Second paragraph."))
        XCTAssertTrue(rendered.string.contains("\n\n"),
                      "Blocks should be separated by \\n\\n; got: \(rendered.string.debugDescription)")
    }

    func test_headingFollowedByParagraph_hasSeparator() {
        let rendered = MarkdownRenderer.render("# Title\n\nBody text here.")
        XCTAssertTrue(rendered.string.contains("Title"))
        XCTAssertTrue(rendered.string.contains("Body text here."))
        XCTAssertTrue(rendered.string.contains("\n\n"))
    }

    // MARK: typography

    func test_heading1_usesLargerBoldFont() {
        let rendered = MarkdownRenderer.render("# Heading One\n\nPara.")
        let titleRange = (rendered.string as NSString).range(of: "Heading One")
        XCTAssertNotEqual(titleRange.location, NSNotFound, "heading text not found in rendered output")

        let font = rendered.attribute(.font, at: titleRange.location, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(font)
        XCTAssertGreaterThan(font?.pointSize ?? 0, 20)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false,
                      "H1 should be bold; got traits: \(String(describing: font?.fontDescriptor.symbolicTraits))")
    }

    func test_inlineBold_appliesBoldTrait() {
        let rendered = MarkdownRenderer.render("plain **bold word** plain")
        let boldRange = (rendered.string as NSString).range(of: "bold word")
        XCTAssertNotEqual(boldRange.location, NSNotFound)

        let font = rendered.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(font)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false,
                      "Bold span should carry bold trait")
    }

    func test_inlineItalic_appliesItalicTrait() {
        let rendered = MarkdownRenderer.render("plain *italic word* plain")
        let italicRange = (rendered.string as NSString).range(of: "italic word")
        XCTAssertNotEqual(italicRange.location, NSNotFound)

        let font = rendered.attribute(.font, at: italicRange.location, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(font)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.italic) ?? false,
                      "Italic span should carry italic trait")
    }

    func test_inlineCode_usesMonospacedFont() {
        let rendered = MarkdownRenderer.render("run `some_code` now")
        let codeRange = (rendered.string as NSString).range(of: "some_code")
        XCTAssertNotEqual(codeRange.location, NSNotFound)

        let font = rendered.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(font)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.monoSpace) ?? false,
                      "Inline code should be monospaced; got \(String(describing: font?.fontName))")
    }

    // MARK: GFM tables

    private static let sampleTable = """
    Intro sentence.

    | Trigger | Claim it makes | Theory |
    |---------|----------------|--------|
    | Failure/struggle | Consecutive failures followed by behavioral change = adaptation | VanLehn's impasse-driven learning (2011) |
    | Progress shortfall | Efficiency dropping below expected baseline reflects a mismatch | COPES Evaluation-Standards (Winne & Hadwin 1998) |

    Trailing paragraph.
    """

    func test_table_emitsNSTextTableBlockOnCellParagraphs() {
        let rendered = MarkdownRenderer.render(Self.sampleTable)
        let ns = rendered.string as NSString
        let triggerRange = ns.range(of: "Trigger")
        XCTAssertNotEqual(triggerRange.location, NSNotFound)

        let style = rendered.attribute(
            .paragraphStyle, at: triggerRange.location, effectiveRange: nil
        ) as? NSParagraphStyle
        XCTAssertNotNil(style, "table header cell must carry a paragraph style")
        let blocks = style?.textBlocks ?? []
        XCTAssertTrue(blocks.contains(where: { $0 is NSTextTableBlock }),
                      "header cell paragraph style must include an NSTextTableBlock; got \(blocks)")
    }

    func test_table_headerCellsAreBold() {
        let rendered = MarkdownRenderer.render(Self.sampleTable)
        let ns = rendered.string as NSString
        let triggerRange = ns.range(of: "Trigger")
        XCTAssertNotEqual(triggerRange.location, NSNotFound)

        let font = rendered.attribute(.font, at: triggerRange.location, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(font)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false,
                      "header row cell should be bold; got \(String(describing: font?.fontName))")
    }

    func test_table_rowsCarrySharedRowID_cellsInDifferentRowsDiffer() {
        let rendered = MarkdownRenderer.render(Self.sampleTable)
        let ns = rendered.string as NSString
        let triggerRange = ns.range(of: "Trigger")          // header row
        let claimRange = ns.range(of: "Claim it makes")      // same header row, next cell
        let failureRange = ns.range(of: "Failure/struggle")  // first data row

        let triggerID = rendered.attribute(.rheaTableRowID, at: triggerRange.location, effectiveRange: nil) as? String
        let claimID = rendered.attribute(.rheaTableRowID, at: claimRange.location, effectiveRange: nil) as? String
        let failureID = rendered.attribute(.rheaTableRowID, at: failureRange.location, effectiveRange: nil) as? String

        XCTAssertNotNil(triggerID)
        XCTAssertNotNil(claimID)
        XCTAssertNotNil(failureID)
        XCTAssertEqual(triggerID, claimID,
                       "cells in the same row must share a row id")
        XCTAssertNotEqual(triggerID, failureID,
                          "cells in different rows must have different row ids")
    }

    func test_table_doesNotStackEachCellAsOwnBlock() {
        // Regression: the old renderer inserted "\n\n" between cells
        // because each cell was a distinct PresentationIntent block.
        // After the fix the only "\n\n" separators should be between
        // non-table blocks (intro, table, trailing paragraph).
        let rendered = MarkdownRenderer.render(Self.sampleTable)
        let occurrences = rendered.string.components(separatedBy: "\n\n").count - 1
        // Expect: Intro ↔ table, table ↔ trailing = 2 gaps.
        XCTAssertEqual(occurrences, 2,
                       "expected 2 block gaps around the table, got \(occurrences) in: \(rendered.string.debugDescription)")
    }

    func test_table_preservesContentInLeftToRightTopToBottomOrder() {
        let rendered = MarkdownRenderer.render(Self.sampleTable)
        let s = rendered.string
        // Header before data; cells of each row appear in order.
        guard let triggerIdx = s.range(of: "Trigger")?.lowerBound,
              let theoryIdx = s.range(of: "Theory")?.lowerBound,
              let failureIdx = s.range(of: "Failure/struggle")?.lowerBound,
              let vanLehnIdx = s.range(of: "VanLehn")?.lowerBound,
              let progressIdx = s.range(of: "Progress shortfall")?.lowerBound
        else {
            XCTFail("expected cell contents missing")
            return
        }
        XCTAssertLessThan(triggerIdx, theoryIdx)
        XCTAssertLessThan(theoryIdx, failureIdx)
        XCTAssertLessThan(failureIdx, vanLehnIdx)
        XCTAssertLessThan(vanLehnIdx, progressIdx)
    }

    // MARK: resilience

    func test_emptyInput_returnsEmptyAttributedString() {
        let rendered = MarkdownRenderer.render("")
        XCTAssertEqual(rendered.length, 0)
    }

    func test_unbalancedSyntax_doesNotCrash() {
        // A markdown snippet with unbalanced emphasis markers
        // should still produce *some* output via the parser's
        // `returnPartiallyParsedIfPossible` policy.
        let rendered = MarkdownRenderer.render("some **unbalanced bold text and then *italic")
        XCTAssertGreaterThan(rendered.length, 0)
    }
}
