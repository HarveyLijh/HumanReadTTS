import Foundation

/// Splits an over-long sentence into chunks that fit comfortably under
/// Kokoro's 510 phoneme-token ceiling. Stays out of the way for normal
/// sentences (returns `[text]` unchanged when `text.count` is below
/// `absoluteMaxChars`), and uses a tiered breakpoint sieve only when
/// the input is genuinely too large.
///
/// Each tier is length-gated: a candidate split is only accepted if
/// the resulting chunks satisfy the minimum-chunk floor, which keeps
/// short comma lists like `"sentence, A, B, C, sentence"` intact
/// while letting an ~580-char clause-stuffed sentence break cleanly
/// at semicolons or commas.
enum KokoroChunker {
    /// Hard ceiling — anything above this MUST be split. Sized so an
    /// English chunk stays under Kokoro's 510-phoneme-token model
    /// limit. Empirically ~1.05 phonemes/char in English, so 380 chars
    /// leaves margin for phone-heavy words.
    static let absoluteMaxChars = 380

    /// Soft target — the sieve aims for chunks at-or-below this size
    /// when natural breakpoints exist. Mirrors Kokoro-FastAPI's 250
    /// phoneme-token target translated to chars.
    static let targetMaxChars = 240

    /// Anti-fragmentation floor. A breakpoint candidate is rejected
    /// if it would produce a piece shorter than this. Prevents
    /// `"sentence, A, B, C, sentence"` from shattering into seven
    /// chunks: each comma-bounded piece is below the floor, so the
    /// sieve declines to split at all.
    static let minChunkChars = 60

    /// Inter-chunk silence padded into the concatenated PCM (~30 ms
    /// at 24 kHz) so the vocoder has a clean re-entry without a click
    /// at the seam.
    static let interChunkSilenceFrames = 720

    /// Returns `text` split into chunks safe for Kokoro synthesis.
    /// Returns `[text]` unchanged when `text.count <= absoluteMaxChars`,
    /// which is the common case.
    static func chunk(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard trimmed.count > absoluteMaxChars else { return [trimmed] }
        return splitOversize(trimmed)
    }

    // MARK: - Tier sieve

    /// Highest-priority tier first. Tiers descend only when the prior
    /// tier failed to produce a length-valid split.
    private enum Tier: CaseIterable {
        case sentenceTerminator   // . ! ?  (rare inside one "sentence" but happens with abbrev. errors)
        case strongClause         // ; : — – (em/en dash)
        case comma                // ,
        case parenthetical        // ( ) [ ] boundaries
        case subordinator         // which / that / because / although / while / when / where ...
        case coordinator          // and / but / or / nor / so / yet / for
    }

    private static func splitOversize(_ text: String) -> [String] {
        for tier in Tier.allCases {
            let candidates = breakpointPositions(in: text, tier: tier)
            guard !candidates.isEmpty else { continue }
            guard let pieces = greedySplit(text, at: candidates) else { continue }
            // If any piece is still oversize, recurse into it with the
            // remaining tiers — but each tier choice is local to the
            // piece, so just call splitOversize again.
            let finalPieces: [String] = pieces.flatMap { piece -> [String] in
                piece.count > absoluteMaxChars ? splitOversize(piece) : [piece]
            }
            if finalPieces.count > 1, finalPieces.allSatisfy({ $0.count <= absoluteMaxChars }) {
                return finalPieces
            }
        }
        // Pathological no-punctuation run — last-resort midpoint word
        // boundary split.
        return hardSplit(text)
    }

    /// Greedy left-to-right packer. For each candidate breakpoint,
    /// emits a chunk if (a) the accumulated chunk is past `minChunkChars`
    /// AND (b) committing the next breakpoint would push us over
    /// `targetMaxChars`. Returns `nil` if no valid chunking emerges
    /// (caller will descend to the next tier).
    private static func greedySplit(_ text: String, at candidates: [Int]) -> [String]? {
        let utf16 = text as NSString
        let total = utf16.length
        guard total > absoluteMaxChars else { return nil }

        var chunks: [String] = []
        var start = 0
        var lastCommitted = 0

        for (idx, pos) in candidates.enumerated() {
            let pieceLen = pos - start
            // Look ahead: what's the next candidate (or end-of-text)?
            let nextPos = idx + 1 < candidates.count ? candidates[idx + 1] : total
            let pieceLenIfWeWait = nextPos - start

            // Skip candidates that would yield a too-short piece...
            if pieceLen < minChunkChars { continue }

            // ...but also skip if we can wait for a better one without
            // exceeding the absolute max. This keeps comma lists glued
            // together until the chunk actually needs to break.
            if pieceLen < targetMaxChars && pieceLenIfWeWait <= absoluteMaxChars {
                continue
            }

            // Commit the split here.
            let range = NSRange(location: start, length: pos - start)
            let piece = utf16.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { chunks.append(piece) }
            start = pos
            lastCommitted = pos
        }

        // Tail.
        if start < total {
            let range = NSRange(location: start, length: total - start)
            let tail = utf16.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                // If the tail is too small, glue it to the previous chunk.
                if let last = chunks.last, tail.count < minChunkChars {
                    chunks[chunks.count - 1] = last + " " + tail
                } else {
                    chunks.append(tail)
                }
            }
        }

        // Failed to actually split? Tell caller to try next tier.
        guard chunks.count > 1 else { return nil }

        // Validate every chunk fits under the hard ceiling — if any
        // doesn't, the recursive caller (splitOversize) will subdivide.
        _ = lastCommitted
        return chunks
    }

    /// Returns UTF-16 positions where a tier-T split *could* occur.
    /// Each position is the offset of the FIRST character of the piece
    /// that follows the breakpoint (i.e. where the new chunk starts).
    private static func breakpointPositions(in text: String, tier: Tier) -> [Int] {
        switch tier {
        case .sentenceTerminator:
            return regexBreakpoints(in: text, pattern: #"[.!?](?:\s+|$)"#, includesTrailingSpace: true)
        case .strongClause:
            // Em-dash (U+2014) and en-dash (U+2013) embedded literally —
            // ICU regex inside a Swift raw string doesn't recognise the
            // `\u{HHHH}` escape, so we use the characters directly.
            return regexBreakpoints(in: text, pattern: #"[;:—–](?:\s+|$)"#, includesTrailingSpace: true)
        case .comma:
            return regexBreakpoints(in: text, pattern: #",(?:\s+|$)"#, includesTrailingSpace: true)
        case .parenthetical:
            // Break right BEFORE an opening paren, or right AFTER a
            // closing one — preserves the bracketed clause as a unit
            // when length permits, or as its own chunk when it doesn't.
            let opens = regexBreakpoints(in: text, pattern: #"\s+(?=[(\[])"#, includesTrailingSpace: false)
            let closes = regexBreakpoints(in: text, pattern: #"[)\]](?:\s+|$)"#, includesTrailingSpace: true)
            return (opens + closes).sorted()
        case .subordinator:
            return wordBreakpoints(in: text, words: subordinators)
        case .coordinator:
            return wordBreakpoints(in: text, words: coordinators)
        }
    }

    /// Subordinating conjunctions / relativizers — natural clause
    /// heads. Listed deliberately conservatively: each one almost
    /// always introduces a parseable clause, so a split immediately
    /// before it gives the listener a sensible boundary.
    private static let subordinators: [String] = [
        "which", "that", "because", "although", "though", "while",
        "whereas", "when", "where", "who", "whom", "whose",
        "if", "unless", "since", "before", "after", "until",
        "as", "however"
    ]

    /// Coordinating conjunctions. Lower priority than subordinators
    /// because "and" inside an enumeration is a worse split point
    /// than "which" introducing a new clause.
    private static let coordinators: [String] = [
        "and", "but", "or", "nor", "so", "yet", "for"
    ]

    /// Returns positions immediately preceding each whole-word
    /// occurrence of any keyword. Word match is case-insensitive
    /// and bounded by `\b` so "andrew" doesn't match "and".
    private static func wordBreakpoints(in text: String, words: [String]) -> [Int] {
        let alternation = words.map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let pattern = #"\s+(?:\#(alternation))\b"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return [] }
        let nsText = text as NSString
        let full = NSRange(location: 0, length: nsText.length)
        var positions: [Int] = []
        regex.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let m = match else { return }
            // Position of the keyword (skip the matched leading whitespace).
            let kwStart = m.range.location + leadingWhitespace(in: nsText, range: m.range)
            positions.append(kwStart)
        }
        return positions
    }

    private static func leadingWhitespace(in text: NSString, range: NSRange) -> Int {
        var n = 0
        while n < range.length {
            let scalar = text.character(at: range.location + n)
            // U+0020 space, U+0009 tab, U+000A LF, U+000D CR, U+00A0 NBSP
            if scalar == 0x20 || scalar == 0x09 || scalar == 0x0A
                || scalar == 0x0D || scalar == 0xA0 { n += 1 } else { break }
        }
        return n
    }

    /// Regex helper: find each match of `pattern`, return the
    /// position immediately AFTER the match (i.e. start of next chunk).
    /// `includesTrailingSpace`: when `true` the regex is expected to
    /// already swallow the post-punct whitespace, so we use match.upperBound.
    private static func regexBreakpoints(
        in text: String, pattern: String, includesTrailingSpace: Bool
    ) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let full = NSRange(location: 0, length: nsText.length)
        var positions: [Int] = []
        regex.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let m = match else { return }
            let pos = includesTrailingSpace
                ? NSMaxRange(m.range)
                : m.range.location
            // Filter out matches at the very end (would yield empty tail).
            if pos > 0 && pos < nsText.length { positions.append(pos) }
        }
        return positions
    }

    /// Last-resort emergency split for pathological no-punctuation runs.
    /// Walks word boundaries from the midpoint outward and picks the
    /// closest space; recurses on each half if either is still oversize.
    private static func hardSplit(_ text: String) -> [String] {
        let nsText = text as NSString
        let total = nsText.length
        guard total > absoluteMaxChars else { return [text] }
        let mid = total / 2
        // Search outward for a whitespace.
        var splitPoint = -1
        for offset in 0..<min(mid, total - mid) {
            for candidate in [mid - offset, mid + offset] {
                guard candidate > 0 && candidate < total else { continue }
                let ch = nsText.character(at: candidate)
                if ch == 0x20 || ch == 0x09 { splitPoint = candidate; break }
            }
            if splitPoint >= 0 { break }
        }
        guard splitPoint > 0 else { return [text] }  // give up — caller passes whole through
        let left = nsText.substring(with: NSRange(location: 0, length: splitPoint))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let right = nsText.substring(with: NSRange(location: splitPoint, length: total - splitPoint))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let leftPieces = left.count > absoluteMaxChars ? hardSplit(left) : [left]
        let rightPieces = right.count > absoluteMaxChars ? hardSplit(right) : [right]
        return leftPieces + rightPieces
    }
}
