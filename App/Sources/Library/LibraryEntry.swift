import Foundation

/// A persisted pointer to a document the user has opened.
///
/// Stores a bookmark for durable resolution across file moves
/// plus a plain `originalPath` string for fast, zero-IO dedup
/// checks in `Library.record(url:)`. Without the cached path,
/// dedup would need to resolve every existing bookmark on each
/// new drop, which on macOS can trigger the Documents/Downloads
/// TCC consent prompt for every bookmark that points into those
/// protected folders. Comparing path strings never touches the
/// filesystem.
///
/// `originalPath` is optional so entries written by older builds
/// (before this field existed) still decode cleanly.
struct LibraryEntry: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let title: String
    let lastOpened: Date
    let bookmarkData: Data
    var originalPath: String?

    init(
        id: UUID = UUID(),
        title: String,
        lastOpened: Date,
        bookmarkData: Data,
        originalPath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.lastOpened = lastOpened
        self.bookmarkData = bookmarkData
        self.originalPath = originalPath
    }
}
