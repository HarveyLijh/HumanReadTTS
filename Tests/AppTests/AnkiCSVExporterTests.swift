import XCTest
@testable import ReadAloudTTS

final class AnkiCSVExporterTests: XCTestCase {

    private func entry(
        _ front: String, _ back: String, context: String = "",
        src: String? = nil, tgt: String? = nil
    ) -> VocabEntry {
        VocabEntry(front: front, back: back, context: context,
                   sourceLanguage: src, targetLanguage: tgt)
    }

    func test_escape_plainFieldUnchanged() {
        XCTAssertEqual(AnkiCSVExporter.escape("hello"), "hello")
        XCTAssertEqual(AnkiCSVExporter.escape("你好"), "你好")
    }

    func test_escape_quotesFieldsWithComma() {
        XCTAssertEqual(AnkiCSVExporter.escape("a, b"), "\"a, b\"")
    }

    func test_escape_doublesInteriorQuotes() {
        XCTAssertEqual(AnkiCSVExporter.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    func test_escape_quotesFieldsWithNewline() {
        XCTAssertEqual(AnkiCSVExporter.escape("line1\nline2"), "\"line1\nline2\"")
    }

    func test_row_ordersFrontBackContextTags() {
        let e = entry("过马路", "to cross the street", context: "他正在过马路。", src: "zh", tgt: "en")
        XCTAssertEqual(
            AnkiCSVExporter.row(for: e),
            "过马路,to cross the street,他正在过马路。,zh en"
        )
    }

    func test_row_escapesContextWithCommaAndQuote() {
        let e = entry("apple", "a fruit", context: "She said, \"an apple a day\".")
        let row = AnkiCSVExporter.row(for: e)
        XCTAssertEqual(row, "apple,a fruit,\"She said, \"\"an apple a day\"\".\",")
    }

    func test_csv_emitsHeaderAndOneRowPerEntry() {
        let entries = [entry("a", "1"), entry("b", "2"), entry("c", "3")]
        let csv = AnkiCSVExporter.csv(from: entries)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertTrue(lines.contains("#separator:Comma"))
        XCTAssertTrue(lines.contains("#tags column:4"))
        // 3 directive lines + 3 data rows.
        XCTAssertEqual(lines.count, 6)
        XCTAssertEqual(lines.suffix(3).map(String.init), ["a,1,,", "b,2,,", "c,3,,"])
    }

    func test_csv_withoutHeader_isDataOnly() {
        let csv = AnkiCSVExporter.csv(from: [entry("a", "1")], includeHeader: false)
        XCTAssertEqual(csv, "a,1,,")
    }

    func test_tags_skipNilAndEmptyLanguages() {
        XCTAssertEqual(AnkiCSVExporter.tags(for: entry("x", "y", src: "zh", tgt: nil)), "zh")
        XCTAssertEqual(AnkiCSVExporter.tags(for: entry("x", "y", src: "", tgt: "en")), "en")
        XCTAssertEqual(AnkiCSVExporter.tags(for: entry("x", "y")), "")
    }
}
