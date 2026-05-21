import Foundation
import Observation

/// User-defined term → spoken-form substitutions applied before
/// text is handed to the synthesizer. Covers the common "say
/// 'P D F' instead of 'pdf'" and "say 'Li-u Ci-xin' not
/// 'Lee-ooo'" cases without pushing users into IPA.
///
/// Matching is case-insensitive, whole-word only. Applied in
/// declaration order so a later entry can override an earlier
/// one if the user wants.
@Observable
@MainActor
final class PronunciationDictionary {
    static let shared = PronunciationDictionary()

    struct Entry: Identifiable, Codable, Hashable, Sendable {
        let id: UUID
        var term: String
        var phonetic: String

        init(id: UUID = UUID(), term: String, phonetic: String) {
            self.id = id
            self.term = term
            self.phonetic = phonetic
        }
    }

    private(set) var entries: [Entry] = []

    private let defaults: UserDefaults
    private let key = "app.readaloudtts.mac.pronunciation.entries.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func add(term: String, phonetic: String) {
        let trimmedTerm = term.trimmingCharacters(in: .whitespaces)
        let trimmedPhonetic = phonetic.trimmingCharacters(in: .whitespaces)
        guard !trimmedTerm.isEmpty, !trimmedPhonetic.isEmpty else { return }
        entries.append(Entry(term: trimmedTerm, phonetic: trimmedPhonetic))
        save()
    }

    func update(_ entry: Entry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        save()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// Apply every entry to `text`, substituting case-insensitive
    /// whole-word matches. Returns the original text if the
    /// dictionary is empty.
    func apply(to text: String) -> String {
        guard !entries.isEmpty else { return text }
        var result = text
        for entry in entries {
            result = Self.replace(in: result, term: entry.term, with: entry.phonetic)
        }
        return result
    }

    /// Case-insensitive whole-word replacement. Whole-word here
    /// means the match is bounded by non-alphanumeric characters
    /// on both sides (or string edges). We don't use \b because
    /// NSRegularExpression's \b misbehaves with non-ASCII terms —
    /// hand-rolling the boundary check keeps CJK terms working
    /// the same way English ones do.
    static func replace(in text: String, term: String, with replacement: String) -> String {
        guard !term.isEmpty else { return text }
        let pattern = NSRegularExpression.escapedPattern(for: term)
        // (?<![A-Za-z0-9_]) lookbehind + (?![A-Za-z0-9_]) lookahead.
        let fullPattern = "(?<![A-Za-z0-9_])\(pattern)(?![A-Za-z0-9_])"
        guard let regex = try? NSRegularExpression(
            pattern: fullPattern,
            options: [.caseInsensitive]
        ) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }

    // MARK: persistence

    private func load() {
        guard let data = defaults.data(forKey: key) else { return }
        if let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }
}
