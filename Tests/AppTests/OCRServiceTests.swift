import XCTest
import AppKit
@testable import ReadAloudTTS

final class OCRServiceTests: XCTestCase {

    /// Render `lines` (top to bottom) as black text on white, returning a
    /// CGImage to feed Vision.
    private func renderImage(
        _ lines: [String],
        size: CGSize = CGSize(width: 700, height: 320)
    ) -> CGImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 44, weight: .regular),
            .foregroundColor: NSColor.black,
        ]
        // AppKit is bottom-left origin; draw from the top down so the
        // first element renders highest on the page.
        var y = size.height - 80
        for line in lines {
            line.draw(at: CGPoint(x: 40, y: y), withAttributes: attrs)
            y -= 90
        }
        image.unlockFocus()
        var rect = NSRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    }

    func test_recognizesPrintedText() async throws {
        let image = renderImage(["Hello World"])
        let text = try await OCRService.shared.recognizeText(in: image, languages: ["en-US"])
        XCTAssertTrue(text.localizedCaseInsensitiveContains("Hello"), "got: \(text)")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("World"), "got: \(text)")
    }

    func test_returnsLinesInReadingOrder() async throws {
        let image = renderImage(["Apple first", "Banana second"])
        let text = try await OCRService.shared.recognizeText(in: image, languages: ["en-US"])
        let lower = text.lowercased()
        guard let apple = lower.range(of: "apple"), let banana = lower.range(of: "banana") else {
            return XCTFail("missing recognized words in: \(text)")
        }
        XCTAssertTrue(apple.lowerBound < banana.lowerBound,
                      "top line should come first: \(text)")
    }

    func test_blankImage_throwsNoText() async {
        let blank = renderImage([])
        do {
            _ = try await OCRService.shared.recognizeText(in: blank)
            XCTFail("blank page should not yield text")
        } catch let error as OCRError {
            XCTAssertEqual(error, OCRError.noText)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

extension OCRError: Equatable {
    public static func == (lhs: OCRError, rhs: OCRError) -> Bool {
        switch (lhs, rhs) {
        case (.noText, .noText): return true
        }
    }
}
