import Foundation

/// A persisted pointer to a document the user has opened.
///
/// Stores a security-scoped bookmark rather than a raw path so the
/// reference survives file moves and is usable when the Release
/// build runs sandboxed. Bookmark resolution happens through
/// `Library.resolve(_:)` which takes care of starting and stopping
/// the security scope.
struct LibraryEntry: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let title: String
    let lastOpened: Date
    let bookmarkData: Data

    init(id: UUID = UUID(), title: String, lastOpened: Date, bookmarkData: Data) {
        self.id = id
        self.title = title
        self.lastOpened = lastOpened
        self.bookmarkData = bookmarkData
    }
}
