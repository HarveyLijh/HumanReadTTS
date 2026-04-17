import XCTest
import PDFKit
@testable import Rhea

final class PDFTextExtractorTests: XCTestCase {

    // MARK: splitOnBlankLines

    func test_splitOnBlankLines_singleParagraph() {
        let result = PDFTextExtractor.splitOnBlankLines("one sentence here")
        XCTAssertEqual(result, ["one sentence here"])
    }

    func test_splitOnBlankLines_twoParagraphs() {
        let input = "first paragraph text\n\nsecond paragraph text"
        XCTAssertEqual(
            PDFTextExtractor.splitOnBlankLines(input),
            ["first paragraph text", "second paragraph text"]
        )
    }

    func test_splitOnBlankLines_preservesSingleNewlinesInsideBlock() {
        let input = "line one\nline two\n\nnext paragraph"
        XCTAssertEqual(
            PDFTextExtractor.splitOnBlankLines(input),
            ["line one\nline two", "next paragraph"]
        )
    }

    func test_splitOnBlankLines_collapsesMultipleBlankLines() {
        let input = "first\n\n\n\nsecond"
        XCTAssertEqual(
            PDFTextExtractor.splitOnBlankLines(input),
            ["first", "second"]
        )
    }

    func test_splitOnBlankLines_dropsEmptyBlocks() {
        let input = "\n\n\nonly block\n\n   \n\n"
        XCTAssertEqual(
            PDFTextExtractor.splitOnBlankLines(input),
            ["only block"]
        )
    }

    func test_splitOnBlankLines_emptyInput() {
        XCTAssertEqual(PDFTextExtractor.splitOnBlankLines(""), [])
        XCTAssertEqual(PDFTextExtractor.splitOnBlankLines("   \n  \n  "), [])
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
    }

    // MARK: helpers

    /// Build a PDFDocument in-memory from an array of per-page text
    /// strings. Each page is rendered as attributed text through
    /// Core Graphics so the resulting PDF has real extractable text.
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
