import XCTest
@testable import Rhea

final class KokoroChunkerTests: XCTestCase {

    // MARK: - Pass-through (the common case)

    func test_shortSentence_isReturnedUnchanged() {
        let text = "This is a perfectly short sentence."
        XCTAssertEqual(KokoroChunker.chunk(text), [text])
    }

    func test_emptyString_returnsEmpty() {
        XCTAssertEqual(KokoroChunker.chunk(""), [])
        XCTAssertEqual(KokoroChunker.chunk("   \n  "), [])
    }

    func test_mediumSentenceJustUnderCeiling_isReturnedUnchanged() {
        // 350-ish chars, under the 380 ceiling — must NOT split even
        // though it has commas. This is the "sentence, A, B, C" rule
        // generalised: short-enough text never gets sliced.
        let text = String(
            repeating: "alpha, beta, gamma, delta, epsilon, ",
            count: 8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertLessThanOrEqual(text.count, KokoroChunker.absoluteMaxChars)
        XCTAssertEqual(KokoroChunker.chunk(text), [text])
    }

    func test_shortCommaList_doesNotShatter() {
        // The user's specific anti-pattern: short comma-list must
        // NOT split. Total length is way under the ceiling.
        let text = "sentence, A, B, C, sentence"
        XCTAssertEqual(KokoroChunker.chunk(text), [text])
    }

    // MARK: - The reported failure case (must split)

    func test_dissertationSentence_splitsAtCommas_noPieceOverCeiling() {
        // The exact ~580-char sentence the user reported. Kokoro
        // crashes through to the system voice on this without
        // chunking; we must produce multiple chunks each under the
        // 380-char absolute ceiling.
        let text = "The architecture's load-bearing methodological commitment is minimal supervision: rather than fully unsupervised plan recognition (which the literature reviewed in §1.3 indicates is not currently published), or fully supervised plan recognition (which does not scale to commercial telemetry where expert annotation is unavailable), the architecture uses two forms of supervision that are obtainable at scale: telemetry-derivable goal labels in testbeds where game state is structured around explicit objectives (educational testbeds in this dissertation), and weak goal labels from large language models in testbeds where stronger supervision is unavailable (commercial testbeds in this dissertation)."
        let chunks = KokoroChunker.chunk(text)
        XCTAssertGreaterThan(chunks.count, 1, "must split this oversize sentence")
        for piece in chunks {
            XCTAssertLessThanOrEqual(
                piece.count, KokoroChunker.absoluteMaxChars,
                "every chunk must fit under the model's hard ceiling"
            )
            XCTAssertGreaterThanOrEqual(
                piece.count, KokoroChunker.minChunkChars,
                "no chunk should be a tiny fragment"
            )
        }
        // Reassembling the chunks should yield the original sentence
        // (modulo whitespace), so no content is lost.
        let rejoined = chunks.joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
        let normalize: (String) -> String = { s in
            s.replacingOccurrences(of: " ,", with: ",")
                .replacingOccurrences(of: " .", with: ".")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        XCTAssertEqual(normalize(rejoined), normalize(text))
    }

    // MARK: - Tier preferences

    func test_overCeilingWithSemicolons_prefersSemicolonOverComma() {
        // Two ~250-char halves joined by a semicolon — total > ceiling.
        // The chunker should split at the semicolon, not at any comma.
        let half = String(repeating: "alpha, beta, gamma, delta, ", count: 9)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let text = "\(half); \(half)"
        XCTAssertGreaterThan(text.count, KokoroChunker.absoluteMaxChars)
        let chunks = KokoroChunker.chunk(text)
        XCTAssertEqual(chunks.count, 2, "should prefer the single semicolon over many commas")
        // First chunk should still carry the trailing semicolon.
        XCTAssertTrue(
            chunks[0].hasSuffix(";"),
            "semicolon stays on the left piece, found: '\(chunks[0].suffix(20))'"
        )
    }

    func test_overCeilingNoStrongPunct_fallsBackToCommas() {
        // Long sentence with only commas — must split at commas with
        // length-aware packing (not every comma).
        let text = String(
            repeating: "the next clause introduces another idea, ",
            count: 12
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertGreaterThan(text.count, KokoroChunker.absoluteMaxChars)
        let chunks = KokoroChunker.chunk(text)
        XCTAssertGreaterThan(chunks.count, 1)
        for piece in chunks {
            XCTAssertLessThanOrEqual(piece.count, KokoroChunker.absoluteMaxChars)
            XCTAssertGreaterThanOrEqual(
                piece.count, KokoroChunker.minChunkChars,
                "comma packing must respect the floor"
            )
        }
    }

    func test_pathologicalNoPunctuation_lastResortMidpointSplit() {
        // Worst case: long text with no punctuation at all. The
        // last-resort hard split should still produce chunks under
        // the ceiling.
        let text = String(repeating: "word ", count: 90)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertGreaterThan(text.count, KokoroChunker.absoluteMaxChars)
        let chunks = KokoroChunker.chunk(text)
        XCTAssertGreaterThan(chunks.count, 1)
        for piece in chunks {
            XCTAssertLessThanOrEqual(piece.count, KokoroChunker.absoluteMaxChars)
        }
    }
}
