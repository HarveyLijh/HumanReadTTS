import Foundation
import Observation

/// Persists the user's saved vocabulary. Entries are kept newest-first
/// and de-duplicated by term (case-insensitive, trimmed) so saving the
/// same word twice updates rather than piles up. Backed by a JSON blob in
/// `UserDefaults`; the injectable `defaults` makes the round-trip
/// testable without touching the user's real store.
@Observable
@MainActor
final class VocabularyStore {
    static let shared = VocabularyStore()

    private(set) var entries: [VocabEntry] = []

    private let defaults: UserDefaults
    private let key = "app.readaloudtts.mac.learning.vocab.v1"

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([VocabEntry].self, from: data) {
            entries = decoded
        }
    }

    /// Inserts `entry` at the front. If its term is already saved the
    /// existing entry is replaced in place (keeping list position) and
    /// the method returns false to signal "updated, not added".
    @discardableResult
    func add(_ entry: VocabEntry) -> Bool {
        if let index = entries.firstIndex(where: { Self.normalized($0.front) == Self.normalized(entry.front) }) {
            entries[index] = entry
            persist()
            return false
        }
        entries.insert(entry, at: 0)
        persist()
        return true
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    func contains(term: String) -> Bool {
        entries.contains { Self.normalized($0.front) == Self.normalized(term) }
    }

    /// The saved vocabulary as an Anki-importable CSV.
    func exportCSV() -> String {
        AnkiCSVExporter.csv(from: entries)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }

    private static func normalized(_ term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
