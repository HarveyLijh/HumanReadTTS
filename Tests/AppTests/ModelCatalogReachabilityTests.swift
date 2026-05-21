import XCTest
@testable import ReadAloudTTS

/// Real-network E2E check that every URL in `ModelCatalog.all` is
/// reachable. HEAD request only — we don't download the bytes,
/// just confirm the server returns a success status. This catches
/// silent URL drift (repo renames, file moves, LFS migration)
/// before a user discovers it by clicking Download.
///
/// Gated behind a filesystem sentinel so CI / quick local runs
/// don't depend on external hosts being up. `xcodebuild` on macOS
/// doesn't forward environment variables into the test runner's
/// process, so an env-var gate would always skip; `/tmp` is
/// readable from inside the test bundle. Opt in with:
///
///     touch /tmp/readaloudtts-run-network-tests && Scripts/test.sh
///
/// Or equivalently: `Scripts/test.sh --network`.
final class ModelCatalogReachabilityTests: XCTestCase {

    override func setUp() async throws {
        let sentinel = "/tmp/readaloudtts-run-network-tests"
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: sentinel),
            "Network tests are opt-in. `touch /tmp/readaloudtts-run-network-tests` and retry."
        )
    }

    func test_kokoroFileURLs_return2xx() async throws {
        for file in ModelCatalog.kokoro.files {
            var request = URLRequest(url: file.downloadURL)
            request.httpMethod = "HEAD"
            // Git-LFS media host sometimes needs a short GET to
            // settle; 10s covers a cold CDN edge.
            request.timeoutInterval = 10

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    XCTFail("Non-HTTP response for \(file.downloadURL)")
                    continue
                }
                // LFS redirects are fine. Accept 2xx after redirect.
                XCTAssertTrue(
                    (200..<300).contains(http.statusCode),
                    "\(file.relativePath) → HTTP \(http.statusCode) at \(file.downloadURL)"
                )
            } catch {
                XCTFail("Request failed for \(file.downloadURL): \(error.localizedDescription)")
            }
        }
    }

    func test_catalog_hasAtLeastOneEntry() {
        XCTAssertFalse(ModelCatalog.all.isEmpty)
    }

    func test_allEntryIDs_areUnique() {
        let ids = ModelCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Duplicate model ids in catalog: \(ids)")
    }
}
