import Foundation

/// Opt-in text cleanup for academic / research PDFs. The goal is
/// to produce speakable prose by removing the short inline
/// artifacts that read badly out loud — bracketed citation keys,
/// parenthetical author-year references, and figure/table caption
/// leaders.
///
/// Applied at speak time in `SpeechPlayer`, not at extract time:
/// the visible document stays exactly as it was, but the
/// synthesizer receives a cleaner string. Users toggle this in
/// Settings → Playback.
enum ResearchCleanup {

    /// Strip bracketed numeric citations: `[12]`, `[12, 13]`,
    /// `[12–15]`. Leaves the surrounding sentence intact and
    /// collapses double-spaces left behind. Does not touch
    /// markdown footnote refs like `[^1]` — those don't appear
    /// in PDF-extracted text anyway.
    static func stripNumericCitations(_ text: String) -> String {
        replace(in: text, pattern: #"\[\s*\d+(?:\s*[,\-–]\s*\d+)*\s*\]"#, with: "")
    }

    /// Strip parenthetical author-year citations: `(Smith 2019)`,
    /// `(Smith and Jones 2019)`, `(Smith et al., 2019)`,
    /// `(Smith et al., 2019, p. 5)`. Tight regex — matches start
    /// with a capital letter and end with a 4-digit year so
    /// general parentheticals like `(see above)` or `(n = 42)`
    /// survive.
    static func stripAuthorYearCitations(_ text: String) -> String {
        let pattern = #"\([A-Z][A-Za-z\-]+(?:(?:\s+(?:and|&)\s+[A-Z][A-Za-z\-]+)|(?:\s+et\s+al\.?))?,?\s+\d{4}[a-z]?(?:[:;,]\s*p{1,2}\.?\s*\d+(?:[\-–]\d+)?)?\s*\)"#
        return replace(in: text, pattern: pattern, with: "")
    }

    /// Strip bracketed author-year citations: `[Smith 2019]`,
    /// `[Smith et al. 2019]`. Same discipline as the parenthetical
    /// variant — must end in a year.
    static func stripBracketedAuthorYear(_ text: String) -> String {
        let pattern = #"\[[A-Z][A-Za-z\-]+(?:(?:\s+(?:and|&)\s+[A-Z][A-Za-z\-]+)|(?:\s+et\s+al\.?))?,?\s+\d{4}[a-z]?\]"#
        return replace(in: text, pattern: pattern, with: "")
    }

    /// Drop whole blocks that are clearly figure / table caption
    /// leaders — lines starting with `Figure N:`, `Fig. N.`,
    /// `Table N:`. The entire block is skipped, not just the
    /// leader, because the caption that follows reads poorly out
    /// loud (usually a dense list of labels).
    static func isFigureOrTableBlock(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(
            pattern: #"^(Figure|Fig\.?|Table|Tbl\.?)\s*\d+\s*[:\.]"#,
            options: [.caseInsensitive]
        ) else { return false }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        return regex.firstMatch(in: trimmed, options: [], range: range) != nil
    }

    /// Apply the full cleanup pass, gated by the user's settings
    /// flags. Collapses any runs of spaces the removals leave
    /// behind so sentences don't read with awkward gaps.
    static func clean(_ text: String, stripCitations: Bool) -> String {
        var out = text
        if stripCitations {
            out = stripNumericCitations(out)
            out = stripAuthorYearCitations(out)
            out = stripBracketedAuthorYear(out)
        }
        // Normalise leftover double-spaces / orphaned punctuation.
        // Order matters: collapse whitespace first so " ," becomes
        // ",", then collapse any doubled separators produced when
        // a citation sat between two punctuation marks.
        out = replace(in: out, pattern: #" {2,}"#, with: " ")
        out = replace(in: out, pattern: #" ([,.;:!?])"#, with: "$1")
        out = replace(in: out, pattern: #"([,;])\s*\1+"#, with: "$1")
        return out.trimmingCharacters(in: .whitespaces)
    }

    // MARK: helpers

    private static func replace(
        in text: String, pattern: String, with replacement: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: replacement
        )
    }
}
