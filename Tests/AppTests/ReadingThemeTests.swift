import XCTest
import AppKit
@testable import ReadAloudTTS

@MainActor
final class ReadingThemeTests: XCTestCase {

    func test_system_keepsAdaptiveSurface() {
        // System imposes neither a background nor an appearance, so readers
        // keep following light/dark mode.
        XCTAssertNil(ReadingTheme.system.background)
        XCTAssertNil(ReadingTheme.system.appearance)
    }

    func test_sepiaAndNight_overrideSurfaceAndAppearance() {
        XCTAssertNotNil(ReadingTheme.sepia.background)
        XCTAssertNotNil(ReadingTheme.night.background)
        XCTAssertEqual(ReadingTheme.sepia.appearance?.name, .aqua)
        XCTAssertEqual(ReadingTheme.night.appearance?.name, .darkAqua)
    }

    func test_allCases_haveStableRawValues() {
        // Persistence relies on these raw values.
        XCTAssertEqual(ReadingTheme.allCases.map(\.rawValue), ["system", "sepia", "night"])
    }

    func test_readerSettings_persistsTheme() {
        let suite = "test.readingtheme.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let first = ReaderSettings(defaults: defaults)
        XCTAssertEqual(first.readingTheme, .system, "default leaves readers unchanged")
        first.readingTheme = .night

        let reloaded = ReaderSettings(defaults: defaults)
        XCTAssertEqual(reloaded.readingTheme, .night)

        reloaded.reset()
        XCTAssertEqual(reloaded.readingTheme, .system)
    }
}
