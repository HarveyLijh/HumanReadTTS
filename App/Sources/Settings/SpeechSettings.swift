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

    private let defaults: UserDefaults
    private let rateKey = "app.rhea.mac.speech.rate.v1"
    private let pitchKey = "app.rhea.mac.speech.pitch.v1"
    private let voiceKey = "app.rhea.mac.speech.voice.v1"
    private let stripCitationsKey = "app.rhea.mac.speech.stripCitations.v1"
    private let skipFigureCaptionsKey = "app.rhea.mac.speech.skipFigureCaptions.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: rateKey) != nil {
            rate = defaults.double(forKey: rateKey)
        }
        if defaults.object(forKey: pitchKey) != nil {
            pitchMultiplier = defaults.double(forKey: pitchKey)
        }
        voiceIdentifier = defaults.string(forKey: voiceKey)
        stripCitations = defaults.bool(forKey: stripCitationsKey)
        skipFigureCaptions = defaults.bool(forKey: skipFigureCaptionsKey)
    }

    func reset() {
        rate = 1.0
        pitchMultiplier = 1.0
        voiceIdentifier = nil
        stripCitations = false
        skipFigureCaptions = false
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
