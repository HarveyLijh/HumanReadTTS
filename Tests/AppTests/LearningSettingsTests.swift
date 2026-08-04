import XCTest
@testable import HumanReadTTS

@MainActor
final class LearningSettingsTests: XCTestCase {

    private func ephemeralDefaults() -> UserDefaults {
        let suite = "test.learning.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func test_defaults_tapToTranslateOffAndTargetIsOffered() {
        let settings = LearningSettings(defaults: ephemeralDefaults())
        XCTAssertFalse(settings.tapToTranslateEnabled, "opt-in gesture is off by default")
        XCTAssertTrue(LearningSettings.offeredLanguages.contains(settings.targetLanguage),
                      "seeded target language is one the picker offers")
    }

    func test_offeredLanguages_includeBilingualFocus() {
        XCTAssertTrue(LearningSettings.offeredLanguages.contains("en"))
        XCTAssertTrue(LearningSettings.offeredLanguages.contains("zh"))
    }

    func test_displayName_resolvesKnownCode() {
        // "zh" localizes to a non-empty, non-code name in English locales.
        let name = LearningSettings.displayName(for: "zh")
        XCTAssertFalse(name.isEmpty)
        XCTAssertNotEqual(name, "zh")
    }

    func test_persistence_survivesReload() {
        let defaults = ephemeralDefaults()
        let first = LearningSettings(defaults: defaults)
        first.tapToTranslateEnabled = true
        first.targetLanguage = "fr"

        let reloaded = LearningSettings(defaults: defaults)
        XCTAssertTrue(reloaded.tapToTranslateEnabled)
        XCTAssertEqual(reloaded.targetLanguage, "fr")
    }

    func test_reset_restoresDefaults() {
        let settings = LearningSettings(defaults: ephemeralDefaults())
        settings.tapToTranslateEnabled = true
        settings.targetLanguage = "ru"
        settings.reset()
        XCTAssertFalse(settings.tapToTranslateEnabled)
        XCTAssertEqual(settings.targetLanguage, LearningSettings.systemTargetLanguage())
    }
}
