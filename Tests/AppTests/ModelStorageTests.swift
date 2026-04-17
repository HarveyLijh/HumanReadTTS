import XCTest
@testable import Rhea

/// Exercises `ModelStorage` against the real filesystem under a
/// uniquely-namespaced test model id so the tests never collide
/// with a real Kokoro installation. Every test cleans up its own
/// directory in tearDown.
final class ModelStorageTests: XCTestCase {

    private var entry: ModelEntry!

    override func setUp() {
        super.setUp()
        let id = "test-storage-\(UUID().uuidString)"
        entry = ModelEntry(
            id: id,
            displayName: "Test Fixture",
            summary: "Test-only catalog entry",
            kind: .ttsEnglish,
            approximateSizeMB: 1,
            files: [],
            engineIntegrated: false,
            upstreamURL: nil,
            fetchStrategy: .manifest
        )
    }

    override func tearDown() {
        if let entry {
            try? ModelStorage.delete(entry)
        }
        entry = nil
        super.tearDown()
    }

    func test_isInstalled_falseWhenDirectoryMissing() {
        XCTAssertFalse(ModelStorage.isInstalled(entry))
    }

    func test_isInstalled_falseWhenMarkerMissing() throws {
        try ModelStorage.ensureExists(for: entry)
        // Directory exists but no marker → partial install.
        XCTAssertFalse(ModelStorage.isInstalled(entry))
    }

    func test_markInstalled_flipsIsInstalledToTrue() throws {
        try ModelStorage.ensureExists(for: entry)
        try ModelStorage.markInstalled(entry)
        XCTAssertTrue(ModelStorage.isInstalled(entry))
    }

    func test_sizeOnDisk_sumsFileSizes() throws {
        try ModelStorage.ensureExists(for: entry)
        let dir = ModelStorage.directory(for: entry)

        let payload1 = Data(count: 1_024)          // 1 KiB
        let payload2 = Data(count: 2_048)          // 2 KiB
        try payload1.write(to: dir.appending(path: "a.bin"))
        try payload2.write(to: dir.appending(path: "b.bin"))

        XCTAssertEqual(ModelStorage.sizeOnDisk(entry), Int64(1_024 + 2_048))
    }

    func test_sizeOnDisk_returnsZeroWhenDirectoryMissing() {
        XCTAssertEqual(ModelStorage.sizeOnDisk(entry), 0)
    }

    func test_delete_removesDirectoryAndMarker() throws {
        try ModelStorage.ensureExists(for: entry)
        try ModelStorage.markInstalled(entry)
        XCTAssertTrue(ModelStorage.isInstalled(entry))

        try ModelStorage.delete(entry)
        XCTAssertFalse(ModelStorage.isInstalled(entry))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: ModelStorage.directory(for: entry).path)
        )
    }

    func test_delete_isIdempotent() throws {
        // Deleting a non-existent directory should not throw.
        XCTAssertNoThrow(try ModelStorage.delete(entry))
    }
}
