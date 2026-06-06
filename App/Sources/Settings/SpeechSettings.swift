import Foundation
import Observation
import AVFoundation

/// App-wide speech preferences. Owned as a single shared instance
/// so the SwiftUI Settings scene (a separate view hierarchy from
/// the main window) and the per-window `SpeechPlayer` see the same
/// state without environment plumbing.
///
/// Persisted to `UserDefaults` on every change. Reads happen at
/// utterance creation time, so slider movement lands at the next
/// sentence boundary rather than mid-utterance — acceptable
/// trade-off for not having to stop-and-restart the synthesizer
/// on every drag tick.
@Observable
@MainActor
final class SpeechSettings {
    static let shared = SpeechSettings()

    /// User-facing speed multiplier. 1.0 is "default", roughly
    /// natural reading pace; 0.5 is half-speed; 2.5 is the
    /// practical upper bound where most voices stay intelligible.
    /// Mapped to `AVSpeechUtterance.rate` at speak time.
    var rate: Double = 1.0 {
        didSet { defaults.set(rate, forKey: rateKey) }
    }

    /// `AVSpeechUtterance.pitchMultiplier` — 0.5 to 2.0, default 1.0.
    var pitchMultiplier: Double = 1.0 {
        didSet { defaults.set(pitchMultiplier, forKey: pitchKey) }
    }

    /// `nil` selects voice automatically per sentence via
    /// `NLLanguageRecognizer`. Setting an explicit identifier
    /// pins every utterance to that voice — useful when the user
    /// has a strong preference for a specific English voice for
    /// papers that are technically multilingual.
    var voiceIdentifier: String? {
        didSet {
            if let voiceIdentifier {
                defaults.set(voiceIdentifier, forKey: voiceKey)
            } else {
                defaults.removeObject(forKey: voiceKey)
            }
        }
    }

    /// When true, `ResearchCleanup.clean` strips inline citations
    /// (`[12]`, `(Smith et al., 2019)`, etc.) from sentence text
    /// before it reaches the synthesizer. Visible document is
    /// unchanged. Default off — changes what the user hears, so
    /// opt-in is safer than opt-out.
    var stripCitations: Bool = false {
        didSet { defaults.set(stripCitations, forKey: stripCitationsKey) }
    }

    /// When true, whole document blocks whose first line looks
    /// like `Figure N:` / `Table N:` are skipped entirely when
    /// loading a PDF. Applied by `PDFTextExtractor` at extract
    /// time (so highlighting and sentence counts match what's
    /// actually playable). Default off.
    var skipFigureCaptions: Bool = false {
        didSet { defaults.set(skipFigureCaptions, forKey: skipFigureCaptionsKey) }
    }

    /// User-editable regex skip patterns. Applied at speak time
    /// via `ResearchCleanup.clean(...)`, so the visible document
    /// stays untouched but the synthesizer receives cleaner text.
    /// Seeded with `SkipRule.builtIns` on first launch; users can
    /// add, edit, disable, or delete custom rules from the Skip
    /// Rules Settings tab. Built-ins are disable-able but not
    /// deletable (preserves the safe default if the user wants
    /// them back).
    var skipRules: [SkipRule] = SkipRule.builtIns {
        didSet { persistSkipRules() }
    }

    /// When true (default), the global "read selection from anywhere"
    /// hotkey restores the user's previous clipboard after briefly
    /// copying their selection to read it. See `SelectionReader`.
    var restoreClipboardAfterReading: Bool = true {
        didSet { defaults.set(restoreClipboardAfterReading, forKey: restoreClipboardKey) }
    }

    /// Default duration (minutes) preselected in the sleep-timer menu.
    /// The timer itself is never armed automatically on launch.
    var sleepTimerMinutes: Int = 15 {
        didSet { defaults.set(sleepTimerMinutes, forKey: sleepTimerMinutesKey) }
    }

    private let defaults: UserDefaults
    private let rateKey = "app.readaloudtts.mac.speech.rate.v1"
    private let pitchKey = "app.readaloudtts.mac.speech.pitch.v1"
    private let voiceKey = "app.readaloudtts.mac.speech.voice.v1"
    private let stripCitationsKey = "app.readaloudtts.mac.speech.stripCitations.v1"
    private let skipFigureCaptionsKey = "app.readaloudtts.mac.speech.skipFigureCaptions.v1"
    private let skipRulesKey = "app.readaloudtts.mac.speech.skipRules.v1"
    private let restoreClipboardKey = "app.readaloudtts.mac.shortcuts.restoreClipboard.v1"
    private let sleepTimerMinutesKey = "app.readaloudtts.mac.playback.sleepTimerMinutes.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: restoreClipboardKey) != nil {
            restoreClipboardAfterReading = defaults.bool(forKey: restoreClipboardKey)
        }
        if defaults.object(forKey: rateKey) != nil {
            rate = defaults.double(forKey: rateKey)
        }
        if defaults.object(forKey: pitchKey) != nil {
            pitchMultiplier = defaults.double(forKey: pitchKey)
        }
        voiceIdentifier = defaults.string(forKey: voiceKey)
        stripCitations = defaults.bool(forKey: stripCitationsKey)
        skipFigureCaptions = defaults.bool(forKey: skipFigureCaptionsKey)
        skipRules = Self.loadSkipRules(from: defaults, key: skipRulesKey)
        if defaults.object(forKey: sleepTimerMinutesKey) != nil {
            sleepTimerMinutes = defaults.integer(forKey: sleepTimerMinutesKey)
        }
    }

    func reset() {
        rate = 1.0
        pitchMultiplier = 1.0
        voiceIdentifier = nil
        stripCitations = false
        skipFigureCaptions = false
        skipRules = SkipRule.builtIns
        restoreClipboardAfterReading = true
        sleepTimerMinutes = 15
    }

    private func persistSkipRules() {
        guard let data = try? JSONEncoder().encode(skipRules) else { return }
        defaults.set(data, forKey: skipRulesKey)
    }

    /// Loads the stored skip rules, or seeds with `SkipRule.builtIns`
    /// on first launch. If the JSON exists but has been externally
    /// edited to drop the built-ins, we re-merge them at the top so
    /// the safe defaults always remain reachable — only toggle-off
    /// hides a built-in, never a corrupt JSON payload.
    private static func loadSkipRules(
        from defaults: UserDefaults, key: String
    ) -> [SkipRule] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SkipRule].self, from: data) else {
            return SkipRule.builtIns
        }
        let existing = Set(decoded.map(\.id))
        let missingBuiltIns = SkipRule.builtIns.filter { !existing.contains($0.id) }
        return missingBuiltIns + decoded
    }

    /// Maps user-facing speed to `AVSpeechUtterance.rate`, clamped
    /// to the framework's documented bounds.
    var avSpeechRate: Float {
        let mapped = AVSpeechUtteranceDefaultSpeechRate * Float(rate)
        return min(
            AVSpeechUtteranceMaximumSpeechRate,
            max(AVSpeechUtteranceMinimumSpeechRate, mapped)
        )
    }
}
