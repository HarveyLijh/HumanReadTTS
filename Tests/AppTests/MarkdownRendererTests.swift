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
