import Foundation

/// A file the user dropped onto the Rhea window.
///
/// Construction is failable: only `.pdf`, `.md`, and `.markdown`
/// extensions are accepted. The validation belongs here (not in the
/// view) so the Sources build phase has one well-tested boundary for
/// "is this a file Rhea can read?"
struct DroppedDocument: Equatable, Hashable {
    enum Kind: String, Equatable, Hashable {
        case pdf
        case markdown
        case epub
    }

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
        default:
            return nil
        }
        self.url = url
    }
}
