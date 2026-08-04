import XCTest
@testable import HumanReadTTS

/// Exercises `Library` record → persist → resolve with a real file
/// on disk and a throwaway `UserDefaults` suite. The key case is
/// the round-trip: a file recorded during one run must resolve
/// back to an openable URL on the next run, regardless of
/// sandbox state.
@MainActor
final class LibraryTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var tempFile: URL!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "app.humanreadtts.mac.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)

        tempFile = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).md")
        try "# hello\n\nworld".write(to: tempFile, atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        if let tempFile { try? FileManager.default.removeItem(at: tempFile) }
        try await super.tearDown()
    }

    func test_record_addsEntryAtTop() {
        let library = Library(defaults: defaults)
        library.record(url: tempFile)
        XCTAssertEqual(library.entries.count, 1)
        XCTAssertEqual(library.entries.first?.title, tempFile.lastPathComponent)
    }

    func test_record_thenResolve_returnsOriginalURL() {
        let library = Library(defaults: defaults)
        library.record(url: tempFile)

        guard let entry = library.entries.first else {
            return XCTFail("no entry after record")
        }
        guard let resolved = library.resolve(entry) else {
            return XCTFail("resolve returned nil — bookmark round-trip broken")
        }
        XCTAssertEqual(resolved.standardizedFileURL.path, tempFile.standardizedFileURL.path)
    }

    func test_recordedEntry_survivesReload() {
        // First Library instance records; a second instance
        // reading the same UserDefaults must see and resolve it.
        let first = Library(defaults: defaults)
        first.record(url: tempFile)

        let second = Library(defaults: defaults)
        XCTAssertEqual(second.entries.count, 1)

        guard let entry = second.entries.first else {
            return XCTFail("persisted entry lost across Library instances")
        }
        XCTAssertNotNil(
            second.resolve(entry),
            "persisted bookmark should resolve on reload"
        )
    }

    func test_dedupe_movesExistingEntryToTop() async throws {
        let library = Library(defaults: defaults)
        library.record(url: tempFile)

        // Record a second, different file.
        let other = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).md")
        try "other".write(to: other, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: other) }
        library.record(url: other)
        XCTAssertEqual(library.entries.count, 2)
        XCTAssertEqual(library.entries.first?.title, other.lastPathComponent)

        // Re-recording the first file should move it to the top,
        // not create a duplicate.
        library.record(url: tempFile)
        XCTAssertEqual(library.entries.count, 2)
        XCTAssertEqual(library.entries.first?.title, tempFile.lastPathComponent)
    }

    // MARK: resume position

    func test_recordPosition_persistsIndex() {
        let library = Library(defaults: defaults)
        library.record(url: tempFile)
        library.recordPosition(url: tempFile, sentenceIndex: 42)
        XCTAssertEqual(library.savedPosition(for: tempFile), 42)
    }

    func test_recordPosition_survivesReload() {
        let first = Library(defaults: defaults)
        first.record(url: tempFile)
        first.recordPosition(url: tempFile, sentenceIndex: 17)

        let second = Library(defaults: defaults)
        XCTAssertEqual(second.savedPosition(for: tempFile), 17)
    }

    func test_record_preservesSavedPosition() {
        let library = Library(defaults: defaults)
        library.record(url: tempFile)
        library.recordPosition(url: tempFile, sentenceIndex: 25)

        // Re-recording (e.g. user reopens from Recents) must not
        // wipe the saved position — dedup removes the entry and
        // re-inserts, which would otherwise lose the index.
        library.record(url: tempFile)
        XCTAssertEqual(library.savedPosition(for: tempFile), 25)
    }

    func test_savedPosition_returnsNilForUntrackedURL() {
        let library = Library(defaults: defaults)
        XCTAssertNil(library.savedPosition(for: tempFile))
    }
}
