import XCTest
import PDFKit
@testable import Rhea

final class PDFTextExtractorTests: XCTestCase {

    // MARK: splitOnBlankLines

    func test_splitOnBlankLines_singleParagraph() {
        let result = PDFTextExtractor.splitOnBlankLines("one sentence here")
        XCTAssertEqual(result.map(\.text), ["one sentence here"])
        XCTAssertEqual(result.map(\.offset), [0])
    }

    func test_splitOnBlankLines_twoParagraphs_carriesOffsets() {
        let input = "first paragraph text\n\nsecond paragraph text"
        let result = PDFTextExtractor.splitOnBlankLines(input)
        XCTAssertEqual(result.map(\.text), ["first paragraph text", "second paragraph text"])
        // First block at 0; second begins after "first paragraph text\n\n" = 22
        XCTAssertEqual(result.map(\.offset), [0, 22])
    }

    func test_splitOnBlankLines_preservesSingleNewlinesInsideBlock() {
        let input = "line one\nline two\n\nnext paragraph"
        XCTAssertEqual(
            PDFTextExtractor.splitOnBlankLines(input).map(\.text),
            ["line one\nline two", "next paragraph"]
        )
    }

    func test_splitOnBlankLines_collapsesMultipleBlankLines() {
        let input = "first\n\n\n\nsecond"
        XCTAssertEqual(
            PDFTextExtractor.splitOnBlankLines(input).map(\.text),
            ["first", "second"]
        )
    }

    func test_splitOnBlankLines_dropsEmptyBlocks() {
        let input = "\n\n\nonly block\n\n   \n\n"
        XCTAssertEqual(
            PDFTextExtractor.splitOnBlankLines(input).map(\.text),
            ["only block"]
        )
    }

    func test_splitOnBlankLines_emptyInput() {
        XCTAssertTrue(PDFTextExtractor.splitOnBlankLines("").isEmpty)
        XCTAssertTrue(PDFTextExtractor.splitOnBlankLines("   \n  \n  ").isEmpty)
    }

    // MARK: extractSync integration

    func test_extractSync_emptyDocument() {
        let document = PDFDocument()
        XCTAssertEqual(PDFTextExtractor.extractSync(document), [])
    }

    func test_extractSync_tagsBlocksWithPageIndex() throws {
        let document = try makePDF(pages: [
            "first page paragraph one\n\nfirst page paragraph two",
            "second page sole paragraph"
        ])
        let blocks = PDFTextExtractor.extractSync(document)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks.map(\.pageIndex), [0, 0, 1])
        XCTAssertEqual(blocks[0].text, "first page paragraph one")
        XCTAssertEqual(blocks[2].text, "second page sole paragraph")
        XCTAssertEqual(blocks[0].offsetInPage, 0)
        XCTAssertGreaterThan(blocks[1].offsetInPage, 0)
    }

    // MARK: helpers

    private func makePDF(pages: [String]) throws -> PDFDocument {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw XCTSkip("CGDataConsumer unavailable")
        }
        var box = pageRect
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw XCTSkip("CGContext PDF creation unavailable")
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Helvetica", size: 12) ?? NSFont.systemFont(ofSize: 12)
        ]

        for text in pages {
            ctx.beginPDFPage(nil)
            let attributed = NSAttributedString(string: text, attributes: attrs)
            let framesetter = CTFramesetterCreateWithAttributedString(attributed)
            let path = CGPath(rect: pageRect.insetBy(dx: 36, dy: 36), transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter, CFRange(location: 0, length: attributed.length), path, nil
            )
            CTFrameDraw(frame, ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()

        guard let document = PDFDocument(data: data as Data) else {
            throw XCTSkip("Could not reconstruct PDFDocument from generated data")
        }
        return document
    }
}
