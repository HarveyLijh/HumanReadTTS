import XCTest
@testable import ReadAloudTTS

@MainActor
final class ReaderSettingsTests: XCTestCase {

    private func ephemeralDefaults() -> UserDefaults {
        let suite = "test.readersettings.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func test_lineFocus_defaultsOff() {
        let settings = ReaderSettings(defaults: ephemeralDefaults())
        XCTAssertFalse(settings.lineFocusEnabled)
        XCTAssertEqual(settings.lineFocusHeight, 52)
    }

    func test_lineFocusHeight_clampsToUsableBand() {
        let settings = ReaderSettings(defaults: ephemeralDefaults())
        settings.lineFocusHeight = 5      // below the floor
        XCTAssertEqual(settings.lineFocusHeight, 32)
        settings.lineFocusHeight = 500    // above the ceiling
        XCTAssertEqual(settings.lineFocusHeight, 140)
    }

    func test_lineFocus_persistsAcrossReload() {
        let defaults = ephemeralDefaults()
        let first = ReaderSettings(defaults: defaults)
        first.lineFocusEnabled = true
        first.lineFocusHeight = 80

        let reloaded = ReaderSettings(defaults: defaults)
        XCTAssertTrue(reloaded.lineFocusEnabled)
        XCTAssertEqual(reloaded.lineFocusHeight, 80)
    }

    func test_reset_restoresLineFocusDefaults() {
        let settings = ReaderSettings(defaults: ephemeralDefaults())
        settings.lineFocusEnabled = true
        settings.lineFocusHeight = 120
        settings.reset()
        XCTAssertFalse(settings.lineFocusEnabled)
        XCTAssertEqual(settings.lineFocusHeight, 52)
    }
}
