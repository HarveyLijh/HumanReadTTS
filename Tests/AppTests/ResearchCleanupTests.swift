import XCTest
@testable import ReadAloudTTS

final class ResearchCleanupTests: XCTestCase {

    // MARK: numeric citations (via built-in SkipRule)

    func test_stripNumeric_single() {
        XCTAssertEqual(
            ResearchCleanup.clean(
                "As shown in [12] the effect is clear.",
                stripCitations: true, skipRules: SkipRule.builtIns
            ),
            "As shown in the effect is clear."
        )
    }

    func test_stripNumeric_multiple() {
        XCTAssertEqual(
            ResearchCleanup.clean(
                "Prior work [12, 13, 14] covers this.",
                stripCitations: true, skipRules: SkipRule.builtIns
            ),
            "Prior work covers this."
        )
    }

    func test_stripNumeric_range() {
        XCTAssertEqual(
            ResearchCleanup.clean(
                "See [12–15] for details.",
                stripCitations: true, skipRules: SkipRule.builtIns
            ),
            "See for details."
        )
    }

    // MARK: built-in skip rules

    func test_latexCite_isRemoved() {
        XCTAssertEqual(
            ResearchCleanup.clean(
                "As shown \\cite{smith2019} above.",
                stripCitations: false, skipRules: SkipRule.builtIns
            ),
            "As shown above."
        )
    }

    func test_citeKeyMarker_isRemoved() {
        XCTAssertEqual(
            ResearchCleanup.clean(
                "See cite:smith2019 for details.",
                stripCitations: false, skipRules: SkipRule.builtIns
            ),
            "See for details."
        )
    }

    func test_customRule_isRemoved() {
        let rules = [
            SkipRule(name: "Fig numbers", pattern: #"\(#\d+\)"#, isEnabled: true)
        ]
        XCTAssertEqual(
            ResearchCleanup.clean(
                "The diagram (#12) above.", stripCitations: false, skipRules: rules
            ),
            "The diagram above."
        )
    }

    func test_disabledRule_doesNotFire() {
        let rules = [
            SkipRule(name: "Curly", pattern: #"\{[^}]+\}"#, isEnabled: false)
        ]
        XCTAssertEqual(
            ResearchCleanup.clean(
                "Keep {braces} intact.", stripCitations: false, skipRules: rules
            ),
            "Keep {braces} intact."
        )
    }

    func test_invalidRule_isSilentlyIgnored() {
        let rules = [
            SkipRule(name: "Busted", pattern: "[", isEnabled: true),
            SkipRule(name: "Good", pattern: #"\bkitten\b"#, isEnabled: true)
        ]
        XCTAssertEqual(
            ResearchCleanup.clean(
                "The kitten sleeps.", stripCitations: false, skipRules: rules
            ),
            "The sleeps."
        )
    }

    // MARK: author-year

    func test_stripAuthorYear_paren() {
        XCTAssertEqual(
            ResearchCleanup.clean("The method (Smith et al., 2019) works.", stripCitations: true),
            "The method works."
        )
    }

    func test_stripAuthorYear_bracket() {
        XCTAssertEqual(
            ResearchCleanup.clean("The method [Smith 2019] works.", stripCitations: true),
            "The method works."
        )
    }

    func test_stripAuthorYear_withPageNumber() {
        XCTAssertEqual(
            ResearchCleanup.clean("Quote (Smith 2019, p. 42) here.", stripCitations: true),
            "Quote here."
        )
    }

    // MARK: preservation

    func test_normalParentheticals_survive() {
        let input = "The sample (n = 42) was measured."
        XCTAssertEqual(
            ResearchCleanup.clean(input, stripCitations: true),
            input
        )
    }

    func test_commaPunctuation_attachesCleanly() {
        XCTAssertEqual(
            ResearchCleanup.clean(
                "Result, [12], matters.", stripCitations: true,
                skipRules: SkipRule.builtIns
            ),
            "Result, matters."
        )
    }

    func test_stripDisabled_returnsInputUnchanged() {
        let input = "See [12] and (Smith 2019)."
        XCTAssertEqual(
            ResearchCleanup.clean(input, stripCitations: false),
            input
        )
    }

    // MARK: figure / table block detection

    func test_figureBlock_isDetected() {
        XCTAssertTrue(ResearchCleanup.isFigureOrTableBlock("Figure 3: results overview.\nMore detail here."))
        XCTAssertTrue(ResearchCleanup.isFigureOrTableBlock("Fig. 5. A diagram of the flow."))
        XCTAssertTrue(ResearchCleanup.isFigureOrTableBlock("Table 2: summary statistics"))
    }

    func test_nonFigureBlock_isNotDetected() {
        XCTAssertFalse(ResearchCleanup.isFigureOrTableBlock("A figure is shown below."))
        XCTAssertFalse(ResearchCleanup.isFigureOrTableBlock("The table contains data."))
        XCTAssertFalse(ResearchCleanup.isFigureOrTableBlock("Figures and tables are referenced."))
    }
}
