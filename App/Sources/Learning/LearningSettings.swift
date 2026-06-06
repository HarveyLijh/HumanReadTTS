import Foundation
import Observation

/// Preferences for the language-learning features: the tap-to-translate
/// gesture and which language the popover translates *into*. Kept apart
/// from `ReaderSettings` so the reading-comfort and study features stay
/// independently resettable. Persisted in `UserDefaults`.
@Observable
@MainActor
final class LearningSettings {
    static let shared = LearningSettings()

    /// When on, Option-double-clicking a word in any reader opens the
    /// translation popover. Off by default so the gesture is opt-in and
    /// the plain reading experience is unchanged.
    var tapToTranslateEnabled: Bool = false {
        didSet { defaults.set(tapToTranslateEnabled, forKey: tapToTranslateKey) }
    }

    /// BCP-47 code the popover translates into. Seeded from the user's
    /// preferred UI language so the gloss reads in their own language.
    var targetLanguage: String {
        didSet { defaults.set(targetLanguage, forKey: targetLanguageKey) }
    }

    /// Languages offered in the "Translate into" picker. A short curated
    /// set covering the app's bilingual focus (English + Chinese) plus the
    /// most common study languages, rather than every BCP-47 code.
    static let offeredLanguages = [
        "en", "zh", "es", "fr", "de", "ja", "ko", "it", "pt", "ru", "ar", "hi",
    ]

    private let defaults: UserDefaults
    private let tapToTranslateKey = "app.readaloudtts.mac.learning.tapToTranslate.v1"
    private let targetLanguageKey = "app.readaloudtts.mac.learning.targetLanguage.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.targetLanguage = defaults.string(forKey: targetLanguageKey) ?? Self.systemTargetLanguage()
        if defaults.object(forKey: tapToTranslateKey) != nil {
            tapToTranslateEnabled = defaults.bool(forKey: tapToTranslateKey)
        }
    }

    /// The user's preferred language reduced to a bare language code,
    /// falling back to English when it isn't one we offer.
    static func systemTargetLanguage() -> String {
        let preferred = Locale.preferredLanguages.first
            .map { Locale.Language(identifier: $0).languageCode?.identifier ?? "en" } ?? "en"
        return offeredLanguages.contains(preferred) ? preferred : "en"
    }

    /// Localized display name for a language code (e.g. "zh" → "Chinese").
    static func displayName(for code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code)?.capitalized(with: .current) ?? code
    }

    func reset() {
        tapToTranslateEnabled = false
        targetLanguage = Self.systemTargetLanguage()
    }
}
