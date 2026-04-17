import XCTest
@testable import Rhea

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

    func test_extensionMatchIsCaseInsensitive() {
        XCTAssertEqual(DroppedDocument(url: URL(filePath: "/tmp/PAPER.PDF"))?.kind, .pdf)
        XCTAssertEqual(DroppedDocument(url: URL(filePath: "/tmp/Notes.MD"))?.kind, .markdown)
    }

    func test_rejectsUnsupportedExtensions() {
        XCTAssertNil(DroppedDocument(url: URL(filePath: "/tmp/document.docx")))
        XCTAssertNil(DroppedDocument(url: URL(filePath: "/tmp/image.png")))
        XCTAssertNil(DroppedDocument(url: URL(filePath: "/tmp/no-extension")))
    }
}
