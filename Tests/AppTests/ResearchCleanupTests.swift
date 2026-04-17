import XCTest
@testable import Rhea

final class ResearchCleanupTests: XCTestCase {

    // MARK: numeric citations

    func test_stripNumeric_single() {
        XCTAssertEqual(
            ResearchCleanup.clean("As shown in [12] the effect is clear.", stripCitations: true),
            "As shown in the effect is clear."
        )
    }

    func test_stripNumeric_multiple() {
        XCTAssertEqual(
            ResearchCleanup.clean("Prior work [12, 13, 14] covers this.", stripCitations: true),
            "Prior work covers this."
        )
    }

    func test_stripNumeric_range() {
        XCTAssertEqual(
            ResearchCleanup.clean("See [12–15] for details.", stripCitations: true),
            "See for details."
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
            ResearchCleanup.clean("Result, [12], matters.", stripCitations: true),
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
