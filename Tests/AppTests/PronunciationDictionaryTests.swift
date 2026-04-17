import XCTest
@testable import Rhea

@MainActor
final class PronunciationDictionaryTests: XCTestCase {

    // MARK: apply — static replacement logic

    func test_replace_wholeWord_caseInsensitive() {
        let out = PronunciationDictionary.replace(
            in: "Open the PDF then pdfutil.",
            term: "PDF",
            with: "P D F"
        )
        XCTAssertEqual(out, "Open the P D F then pdfutil.")
    }

    func test_replace_doesNotMatchSubstring() {
        let out = PronunciationDictionary.replace(
            in: "pdfutil is not a PDF",
            term: "PDF",
            with: "P D F"
        )
        XCTAssertEqual(out, "pdfutil is not a P D F")
    }

    func test_replace_handlesPunctuationBoundary() {
        let out = PronunciationDictionary.replace(
            in: "Try PDF, PDFs, and PDF.",
            term: "PDF",
            with: "P D F"
        )
        XCTAssertEqual(out, "Try P D F, PDFs, and P D F.")
    }

    func test_replace_emptyTerm_returnsInput() {
        let input = "abc"
        XCTAssertEqual(PronunciationDictionary.replace(in: input, term: "", with: "xyz"), input)
    }

    func test_replace_termNotPresent() {
        let input = "No matches here"
        XCTAssertEqual(
            PronunciationDictionary.replace(in: input, term: "PDF", with: "P D F"),
            input
        )
    }

    // MARK: dictionary behaviour

    func test_apply_runsEachEntryInOrder() {
        let suite = "app.rhea.mac.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let dict = PronunciationDictionary(defaults: defaults)

        dict.add(term: "PDF", phonetic: "P D F")
        dict.add(term: "AI", phonetic: "A I")

        let out = dict.apply(to: "The PDF uses AI.")
        XCTAssertEqual(out, "The P D F uses A I.")
    }

    func test_add_thenReload_persists() {
        let suite = "app.rhea.mac.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = PronunciationDictionary(defaults: defaults)
        first.add(term: "Rhea", phonetic: "Ree-uh")

        let second = PronunciationDictionary(defaults: defaults)
        XCTAssertEqual(second.entries.count, 1)
        XCTAssertEqual(second.entries.first?.term, "Rhea")
    }

    func test_add_rejectsEmptyInputs() {
        let suite = "app.rhea.mac.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let dict = PronunciationDictionary(defaults: defaults)

        dict.add(term: "", phonetic: "foo")
        dict.add(term: "foo", phonetic: "")
        dict.add(term: "  ", phonetic: "  ")
        XCTAssertTrue(dict.entries.isEmpty)
    }

    func test_remove_dropsEntry() {
        let suite = "app.rhea.mac.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let dict = PronunciationDictionary(defaults: defaults)
        dict.add(term: "A", phonetic: "alpha")
        dict.add(term: "B", phonetic: "beta")
        let idA = dict.entries.first(where: { $0.term == "A" })!.id
        dict.remove(id: idA)
        XCTAssertEqual(dict.entries.map(\.term), ["B"])
    }

    func test_apply_withEmptyDictionary_isNoOp() {
        let suite = "app.rhea.mac.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let dict = PronunciationDictionary(defaults: defaults)
        XCTAssertEqual(dict.apply(to: "unchanged"), "unchanged")
    }
}
