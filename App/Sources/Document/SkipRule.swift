import Foundation

/// A user-editable skip pattern applied to sentence text before it
/// reaches the synthesizer. Each rule pairs a human-readable name
/// with a regular expression; matches are replaced with the empty
/// string (leaving surrounding punctuation for `ResearchCleanup` to
/// tidy).
///
/// Rules are stored as JSON in `UserDefaults` by `SpeechSettings`
/// so the list survives app restarts and syncs with iCloud Backup.
/// Three built-in rules ship enabled by default — covering the
/// three most common noisy-in-speech patterns in papers — and the
/// user can add any number of custom patterns from the Skip Rules
/// Settings tab.
struct SkipRule: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var name: String
    var pattern: String
    var isEnabled: Bool
    var isBuiltIn: Bool

    init(
        id: UUID = UUID(),
        name: String,
        pattern: String,
        isEnabled: Bool = true,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
    }

    /// Whether `pattern` compiles as a valid `NSRegularExpression`.
    /// The Settings UI blocks save on `false` so the player never
    /// encounters a bogus pattern at speak time.
    var compiles: Bool {
        (try? NSRegularExpression(pattern: pattern)) != nil
    }

    /// The three canonical built-ins Rhea ships with, enabled by
    /// default. Users can disable them in the Skip Rules tab (they
    /// can't delete them — toggling off is the "safe" affordance).
    static var builtIns: [SkipRule] {
        [
            SkipRule(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
                name: "Numeric citations — [1], [1, 2], [1-3]",
                pattern: #"\[\s*\d+(?:\s*[,\-–]\s*\d+)*\s*\]"#,
                isEnabled: true,
                isBuiltIn: true
            ),
            SkipRule(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
                name: "LaTeX cite commands — \\cite{...}",
                pattern: #"\\(?:cite|citep|citet|ref|label|eqref)\{[^}]*\}"#,
                isEnabled: true,
                isBuiltIn: true
            ),
            SkipRule(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!,
                name: "Inline cite markers — cite:key",
                pattern: #"\bcite:\S+"#,
                isEnabled: true,
                isBuiltIn: true
            ),
            SkipRule(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000004")!,
                name: "Author-year citations — [Smith et al., 2020; Jones, 2021]",
                pattern: #"\[[A-Z][\w'.\-]*(?:\s+(?:and|&)\s+[A-Z][\w'.\-]*|\s+et\s+al\.?)*,?\s+\d{4}[a-z]?(?:\s*;\s*[A-Z][\w'.\-]*(?:\s+(?:and|&)\s+[A-Z][\w'.\-]*|\s+et\s+al\.?)*,?\s+\d{4}[a-z]?)*\s*\]"#,
                isEnabled: true,
                isBuiltIn: true
            ),
        ]
    }
}
