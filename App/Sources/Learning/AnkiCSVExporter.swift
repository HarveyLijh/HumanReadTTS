import Foundation

/// One saved vocabulary item. Shared by the (later) vocabulary store and
/// the Anki exporter. `front` is the term as it appeared, `back` its
/// gloss/translation, `context` the sentence it was found in, and the
/// language pair becomes Anki tags.
struct VocabEntry: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var front: String
    var back: String
    var context: String
    var sourceLanguage: String?
    var targetLanguage: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        front: String,
        back: String,
        context: String = "",
        sourceLanguage: String? = nil,
        targetLanguage: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.front = front
        self.back = back
        self.context = context
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.createdAt = createdAt
    }
}

/// Builds an Anki-importable CSV from saved vocabulary. Every field is
/// RFC 4180 quoted, so commas, double quotes, and newlines — common in
/// example sentences, and the usual cause of a botched import — round-
/// trip intact. CJK text needs no special handling: UTF-8 carries it and
/// quoting only triggers on the structural characters.
enum AnkiCSVExporter {
    /// Column order written for each note: Front, Back, Context, Tags.
    static let columns = ["Front", "Back", "Context", "Tags"]

    /// Returns the CSV text. With `includeHeader`, prepends Anki import
    /// directives (comma separator, tags in column 4) that let recent
    /// Anki map the file without the manual column dialog.
    static func csv(from entries: [VocabEntry], includeHeader: Bool = true) -> String {
        var lines: [String] = []
        if includeHeader {
            lines.append("#separator:Comma")
            lines.append("#html:false")
            lines.append("#tags column:4")
        }
        for entry in entries {
            lines.append(row(for: entry))
        }
        return lines.joined(separator: "\n")
    }

    /// One CSV record for an entry.
    static func row(for entry: VocabEntry) -> String {
        [entry.front, entry.back, entry.context, tags(for: entry)]
            .map(escape)
            .joined(separator: ",")
    }

    /// Space-separated Anki tags from the language pair (Anki tags cannot
    /// contain spaces, and a `src-tgt` shape reads well in the browser).
    static func tags(for entry: VocabEntry) -> String {
        [entry.sourceLanguage, entry.targetLanguage]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// RFC 4180 field escaping: wrap in double quotes and double any
    /// interior quote when the field contains a comma, quote, CR, or LF.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
