import Foundation
import PDFKit
import AppKit

/// Loads a document's sentences independently of the reader views so
/// the "Generate Audio…" sheet can work on any library entry —
/// including ones the user hasn't opened in this session. Mirrors
/// each reader's existing extract → segment pipeline:
/// - PDF: `PDFTextExtractor` → `SentenceSegmenter`
/// - Markdown: `MarkdownRenderer` → plain text → `SentenceSegmenter`
/// - EPUB: `EPUBLoader` → plain text → `SentenceSegmenter`
/// - DOCX: `DOCXLoader` → plain text → `SentenceSegmenter`
/// - Plain text: `String(contentsOf:)` → `SentenceSegmenter`
///
/// Keeping the split here (instead of reaching into each reader
/// view) means the sheet doesn't require a live SwiftUI subtree or
/// an open document, which is exactly what right-clicking a sidebar
/// row needs.
@MainActor
enum ExportSentenceLoader {
    enum LoadError: LocalizedError {
        case unsupportedFormat
        case pdfOpenFailed
        case markdownReadFailed(String)
        case epubReadFailed(String)
        case docxReadFailed(String)
        case textReadFailed(String)
        case imageReadFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat: return "Unsupported document format."
            case .pdfOpenFailed: return "Couldn't open the PDF."
            case .markdownReadFailed(let m): return "Couldn't read Markdown: \(m)"
            case .epubReadFailed(let m): return "Couldn't read EPUB: \(m)"
            case .docxReadFailed(let m): return "Couldn't read DOCX: \(m)"
            case .textReadFailed(let m): return "Couldn't read text file: \(m)"
            case .imageReadFailed(let m): return "Couldn't read image: \(m)"
            }
        }
    }

    static func load(url: URL) async throws -> [Sentence] {
        guard let doc = DroppedDocument(url: url) else {
            throw LoadError.unsupportedFormat
        }
        switch doc.kind {
        case .pdf:
            guard let pdf = PDFDocument(url: url) else {
                throw LoadError.pdfOpenFailed
            }
            let skipFigures = SpeechSettings.shared.skipFigureCaptions
            let blocks = await PDFTextExtractor.extract(
                pdf, skipFigureCaptions: skipFigures
            )
            return await SentenceSegmenter.segment(blocks)
        case .markdown:
            do {
                let raw = try String(contentsOf: url, encoding: .utf8)
                let rendered = MarkdownRenderer.render(raw)
                let block = DocumentBlock(
                    text: rendered.string, pageIndex: 0, offsetInPage: 0
                )
                return await SentenceSegmenter.segment([block])
            } catch {
                throw LoadError.markdownReadFailed(error.localizedDescription)
            }
        case .epub:
            do {
                let attributed = try await EPUBLoader.load(url: url)
                let block = DocumentBlock(
                    text: attributed.string, pageIndex: 0, offsetInPage: 0
                )
                return await SentenceSegmenter.segment([block])
            } catch {
                throw LoadError.epubReadFailed(error.localizedDescription)
            }
        case .docx:
            do {
                let attributed = try await DOCXLoader.load(url: url)
                let block = DocumentBlock(
                    text: attributed.string, pageIndex: 0, offsetInPage: 0
                )
                return await SentenceSegmenter.segment([block])
            } catch {
                throw LoadError.docxReadFailed(error.localizedDescription)
            }
        case .text:
            do {
                let raw: String
                do {
                    raw = try String(contentsOf: url, encoding: .utf8)
                } catch {
                    let data = try Data(contentsOf: url)
                    raw = String(decoding: data, as: UTF8.self)
                }
                let block = DocumentBlock(
                    text: raw, pageIndex: 0, offsetInPage: 0
                )
                return await SentenceSegmenter.segment([block])
            } catch {
                throw LoadError.textReadFailed(error.localizedDescription)
            }
        case .image:
            guard let image = NSImage(contentsOf: url),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw LoadError.imageReadFailed("the image couldn't be opened")
            }
            do {
                let text = try await OCRService.shared.recognizeText(
                    in: cgImage,
                    languages: SpeechSettings.shared.ocrRecognitionLanguages
                )
                let block = DocumentBlock(text: text, pageIndex: 0, offsetInPage: 0)
                return await SentenceSegmenter.segment([block])
            } catch {
                throw LoadError.imageReadFailed(error.localizedDescription)
            }
        }
    }
}
