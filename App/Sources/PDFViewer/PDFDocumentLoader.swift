import Foundation
import PDFKit

// PDFDocument is thread-safe when not shared across threads. We init
// it on a background task and hand the unique reference back to the
// main actor exactly once — safe in region-isolation terms, but the
// type itself isn't marked Sendable in the SDK. Mark it retroactively.
extension PDFDocument: @unchecked @retroactive Sendable {}

/// Reads a `PDFDocument` from disk off the main thread.
///
/// `PDFDocument(url:)` is synchronous and can take noticeable time
/// for large or scanned PDFs. Wrapping it in a detached Task keeps
/// the UI responsive without forcing PDFKit through a custom queue.
enum PDFDocumentLoader {
    static func load(url: URL) async -> PDFDocument? {
        await Task.detached(priority: .userInitiated) {
            PDFDocument(url: url)
        }.value
    }
}
