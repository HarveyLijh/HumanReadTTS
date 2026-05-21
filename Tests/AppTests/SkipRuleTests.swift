import XCTest
@testable import ReadAloudTTS

final class SkipRuleTests: XCTestCase {
    func test_builtIns_haveStableIDsAcrossCalls() {
        // The built-ins use fixed UUIDs so that persisted user
        // customisations (toggled-off state on a specific built-in)
        // survive an upgrade. If the IDs drift, a disabled rule
        // turns itself back on silently at next launch.
        let first = SkipRule.builtIns.map(\.id)
        let second = SkipRule.builtIns.map(\.id)
        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first).count, first.count)
    }

    func test_builtIns_areEnabledAndMarkedBuiltIn() {
        for rule in SkipRule.builtIns {
            XCTAssertTrue(rule.isEnabled, "\(rule.name) must start enabled")
            XCTAssertTrue(rule.isBuiltIn, "\(rule.name) must be marked built-in")
            XCTAssertTrue(rule.compiles, "\(rule.name) pattern must compile")
        }
    }

    func test_codableRoundTrip_preservesFields() throws {
        let rule = SkipRule(
            name: "Tech codes", pattern: #"\bSKU-\d+\b"#,
            isEnabled: false, isBuiltIn: false
        )
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(SkipRule.self, from: data)
        XCTAssertEqual(decoded, rule)
    }

    func test_invalidPatternReportsAsNotCompiling() {
        let rule = SkipRule(name: "Bad", pattern: "[", isEnabled: true)
        XCTAssertFalse(rule.compiles)
    }
}
