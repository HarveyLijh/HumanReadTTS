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

    private let defaults: UserDefaults
    private let rateKey = "app.rhea.mac.speech.rate.v1"
    private let pitchKey = "app.rhea.mac.speech.pitch.v1"
    private let voiceKey = "app.rhea.mac.speech.voice.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: rateKey) != nil {
            rate = defaults.double(forKey: rateKey)
        }
        if defaults.object(forKey: pitchKey) != nil {
            pitchMultiplier = defaults.double(forKey: pitchKey)
        }
        voiceIdentifier = defaults.string(forKey: voiceKey)
    }

    func reset() {
        rate = 1.0
        pitchMultiplier = 1.0
        voiceIdentifier = nil
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
