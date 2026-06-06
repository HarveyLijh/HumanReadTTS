import AVFoundation

/// Speaks a single word for the translation popover's "hear it" button.
/// Deliberately separate from `SpeechPlayer` so pronouncing a looked-up
/// word never disturbs an in-progress document read: it owns its own
/// lightweight `AVSpeechSynthesizer` and picks a voice matching the
/// word's source language.
@MainActor
final class WordPronouncer {
    static let shared = WordPronouncer()

    private let synthesizer = AVSpeechSynthesizer()

    /// Speak `text`, preferring a voice for `language` (a bare language
    /// code like "zh"). Interrupts any word still being pronounced.
    func speak(_ text: String, language: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: trimmed)
        if let language, let voice = AVSpeechSynthesisVoice(language: Self.bcp47(for: language)) {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }

    /// `AVSpeechSynthesisVoice(language:)` wants a region-qualified tag,
    /// so map the bare codes we detect to a sensible default region.
    static func bcp47(for code: String) -> String {
        if code.contains("-") { return code }
        switch code {
        case "en": return "en-US"
        case "zh": return "zh-CN"
        case "es": return "es-ES"
        case "fr": return "fr-FR"
        case "de": return "de-DE"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        case "it": return "it-IT"
        case "pt": return "pt-BR"
        case "ru": return "ru-RU"
        case "ar": return "ar-SA"
        case "hi": return "hi-IN"
        default: return code
        }
    }
}
