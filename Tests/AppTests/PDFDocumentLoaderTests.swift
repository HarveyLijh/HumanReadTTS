import XCTest
import PDFKit
@testable import HumanReadTTS

final class PDFDocumentLoaderTests: XCTestCase {

    func test_loadsValidPDF() async throws {
        let url = try makeBlankPDF()
        defer { try? FileManager.default.removeItem(at: url) }

        let document = await PDFDocumentLoader.load(url: url)
        XCTAssertNotNil(document)
        XCTAssertEqual(document?.pageCount, 1)
    }

    func test_returnsNilForNonexistentFile() async {
        let url = URL(filePath: "/tmp/humanreadtts-does-not-exist-\(UUID().uuidString).pdf")
        let document = await PDFDocumentLoader.load(url: url)
        XCTAssertNil(document)
    }

    func test_returnsNilForNonPDFContents() async throws {
        let url = URL.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        try "this is not a PDF".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = await PDFDocumentLoader.load(url: url)
        XCTAssertNil(document)
    }

    // MARK: helpers

    /// Generates a single-page blank US-letter PDF on disk via Core
    /// Graphics. Avoids committing a binary fixture to the repo.
    private func makeBlankPDF() throws -> URL {
        let url = URL.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw XCTSkip("CGContext PDF creation unavailable in this environment")
        }
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        return url
    }
}
