import Foundation

/// A file the user dropped onto the ReadAloudTTS window.
///
/// Construction is failable: only readable formats are accepted.
/// The validation belongs here (not in the view) so the Sources build
/// phase has one well-tested boundary for "is this a file ReadAloudTTS
/// can read?" Today: PDF, Markdown, EPUB, plain text, DOCX, and images
/// (read via on-device OCR).
struct DroppedDocument: Equatable, Hashable {
    enum Kind: String, Equatable, Hashable {
        case pdf
        case markdown
        case epub
        case text
        case docx
        case image
    }

    /// Image extensions read through OCR.
    static let imageExtensions = ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp"]

    let url: URL
    let kind: Kind

    init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "pdf":
            self.kind = .pdf
        case "md", "markdown":
            self.kind = .markdown
        case "epub":
            self.kind = .epub
        case "txt", "text", "log":
            self.kind = .text
        case "docx":
            self.kind = .docx
        case let ext where Self.imageExtensions.contains(ext):
            self.kind = .image
        default:
            return nil
        }
        self.url = url
    }
}
