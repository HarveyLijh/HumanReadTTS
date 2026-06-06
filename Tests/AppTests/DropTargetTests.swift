import XCTest
@testable import ReadAloudTTS

final class DroppedDocumentTests: XCTestCase {
    func test_acceptsPDFExtension() {
        let url = URL(filePath: "/tmp/paper.pdf")
        let document = DroppedDocument(url: url)
        XCTAssertNotNil(document)
        XCTAssertEqual(document?.kind, .pdf)
        XCTAssertEqual(document?.url, url)
    }

    func test_acceptsMarkdownExtensions() {
        XCTAssertEqual(DroppedDocument(url: URL(filePath: "/tmp/notes.md"))?.kind, .markdown)
        XCTAssertEqual(DroppedDocument(url: URL(filePath: "/tmp/README.markdown"))?.kind, .markdown)
    }

    func test_acceptsEPUBExtension() {
        XCTAssertEqual(DroppedDocument(url: URL(filePath: "/tmp/book.epub"))?.kind, .epub)
    }

    func test_acceptsDOCXExtension() {
        XCTAssertEqual(DroppedDocument(url: URL(filePath: "/tmp/draft.docx"))?.kind, .docx)
    }

    func test_acceptsPlainTextExtensions() {
        XCTAssertEqual(DroppedDocument(url: URL(filePath: "/tmp/notes.txt"))?.kind, .text)
        XCTAssertEqual(DroppedDocument(url: URL(filePath: "/tmp/log.log"))?.kind, .text)
        XCTAssertEqual(DroppedDocument(url: URL(filePath: "/tmp/data.text"))?.kind, .text)
    }

    func test_extensionMatchIsCaseInsensitive() {
        XCTAssertEqual(DroppedDocument(url: URL(filePath: "/tmp/PAPER.PDF"))?.kind, .pdf)
        XCTAssertEqual(DroppedDocument(url: URL(filePath: "/tmp/Notes.MD"))?.kind, .markdown)
        XCTAssertEqual(DroppedDocument(url: URL(filePath: "/tmp/Draft.DOCX"))?.kind, .docx)
        XCTAssertEqual(DroppedDocument(url: URL(filePath: "/tmp/Memo.TXT"))?.kind, .text)
    }

    func test_acceptsImageExtensionsAsOCR() {
        for ext in DroppedDocument.imageExtensions {
            XCTAssertEqual(DroppedDocument(url: URL(filePath: "/tmp/scan.\(ext)"))?.kind, .image,
                           "\(ext) should route to OCR")
            XCTAssertEqual(DroppedDocument(url: URL(filePath: "/tmp/SCAN.\(ext.uppercased())"))?.kind, .image,
                           "\(ext) uppercase should route to OCR")
        }
    }

    func test_rejectsUnsupportedExtensions() {
        XCTAssertNil(DroppedDocument(url: URL(filePath: "/tmp/document.doc")))
        XCTAssertNil(DroppedDocument(url: URL(filePath: "/tmp/archive.zip")))
        XCTAssertNil(DroppedDocument(url: URL(filePath: "/tmp/no-extension")))
    }
}
