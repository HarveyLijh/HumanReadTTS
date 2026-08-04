import XCTest
@testable import HumanReadTTS

@MainActor
final class VocabularyStoreTests: XCTestCase {

    private func ephemeralDefaults() -> UserDefaults {
        let suite = "test.vocab.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func entry(_ front: String, _ back: String = "gloss") -> VocabEntry {
        VocabEntry(front: front, back: back)
    }

    func test_add_insertsNewestFirst() {
        let store = VocabularyStore(defaults: ephemeralDefaults())
        XCTAssertTrue(store.add(entry("first")))
        XCTAssertTrue(store.add(entry("second")))
        XCTAssertEqual(store.entries.map(\.front), ["second", "first"])
    }

    func test_add_duplicateTerm_updatesInPlaceAndReturnsFalse() {
        let store = VocabularyStore(defaults: ephemeralDefaults())
        store.add(entry("apple", "fruit"))
        store.add(entry("banana"))
        let inserted = store.add(VocabEntry(front: " Apple ", back: "a red fruit"))
        XCTAssertFalse(inserted, "same term (case/space-insensitive) updates")
        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(store.entries.first(where: { $0.front.trimmingCharacters(in: .whitespaces) == "Apple" })?.back,
                       "a red fruit")
    }

    func test_remove_byID() {
        let store = VocabularyStore(defaults: ephemeralDefaults())
        let a = entry("a"); store.add(a); store.add(entry("b"))
        store.remove(a.id)
        XCTAssertEqual(store.count, 1)
        XCTAssertFalse(store.contains(term: "a"))
    }

    func test_contains_isCaseAndWhitespaceInsensitive() {
        let store = VocabularyStore(defaults: ephemeralDefaults())
        store.add(entry("Crossing"))
        XCTAssertTrue(store.contains(term: "  crossing "))
        XCTAssertFalse(store.contains(term: "cross"))
    }

    func test_persistence_survivesReload() {
        let defaults = ephemeralDefaults()
        let first = VocabularyStore(defaults: defaults)
        first.add(VocabEntry(front: "过马路", back: "cross the street", context: "他正在过马路。"))
        first.add(entry("hello"))

        let reloaded = VocabularyStore(defaults: defaults)
        XCTAssertEqual(reloaded.count, 2)
        XCTAssertEqual(reloaded.entries.map(\.front), ["hello", "过马路"])
        XCTAssertEqual(reloaded.entries.last?.context, "他正在过马路。")
    }

    func test_clear_empties_andPersists() {
        let defaults = ephemeralDefaults()
        let store = VocabularyStore(defaults: defaults)
        store.add(entry("x")); store.add(entry("y"))
        store.clear()
        XCTAssertTrue(store.isEmpty)
        XCTAssertTrue(VocabularyStore(defaults: defaults).isEmpty)
    }

    func test_exportCSV_includesEntries() {
        let store = VocabularyStore(defaults: ephemeralDefaults())
        store.add(VocabEntry(front: "word", back: "meaning", sourceLanguage: "en", targetLanguage: "zh"))
        let csv = store.exportCSV()
        XCTAssertTrue(csv.contains("word,meaning,,en zh"))
    }
}
