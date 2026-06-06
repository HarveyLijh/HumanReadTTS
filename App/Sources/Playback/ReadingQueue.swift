import Foundation
import Observation

/// An ordered list of text snippets to read one after another with the
/// menu-bar reader. The model is intentionally pure — it holds items and
/// the auto-advance preference and nothing else. `MenuBarCommand` owns
/// the side effects: it appends here, sets `SpeechPlayer.onReachedEnd` to
/// pull the next item when a read finishes, and reads whatever
/// `dequeueNext()` returns.
@Observable
@MainActor
final class ReadingQueue {
    static let shared = ReadingQueue()

    struct Item: Identifiable, Equatable {
        let id: UUID
        var title: String
        var text: String

        init(id: UUID = UUID(), title: String, text: String) {
            self.id = id
            self.title = title
            self.text = text
        }
    }

    private(set) var items: [Item] = []

    /// When true, the menu-bar reader pulls the next item automatically
    /// once the current read finishes. Off lets a read end without
    /// chaining. Persisted by `MenuBarCommand` via `SpeechSettings`.
    var autoAdvance: Bool = true

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    /// Appends `text` as a new item. The title is the first words of the
    /// text unless one is supplied. Empty/whitespace text is ignored so a
    /// stray "Queue clipboard" with nothing copied is a no-op.
    @discardableResult
    func enqueue(_ text: String, title: String? = nil) -> Item? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let item = Item(title: title ?? Self.derivedTitle(from: trimmed), text: text)
        items.append(item)
        return item
    }

    /// Removes and returns the first item, or nil when empty.
    @discardableResult
    func dequeueNext() -> Item? {
        guard !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    func clear() {
        items.removeAll()
    }

    /// First few words of `text`, one line, for the item label.
    static func derivedTitle(from text: String, maxLength: Int = 42) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > maxLength else { return collapsed }
        return String(collapsed.prefix(maxLength)) + "…"
    }
}
