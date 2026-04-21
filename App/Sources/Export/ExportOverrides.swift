import Foundation

/// Per-job speech parameters that override `SpeechSettings.shared`
/// for the duration of one export. The live-playback synthesizer
/// keeps reading from the shared settings, so the user can start a
/// long export in a different voice / rate than they're currently
/// listening with.
///
/// Every field is optional — `nil` means "fall back to
/// `SpeechSettings.shared`", letting callers override only the
/// parameters that matter for the job.
struct ExportOverrides: Equatable, Sendable {
    var voiceIdentifier: String?
    var rate: Double?
    var pitchMultiplier: Double?

    static let none = ExportOverrides()

    /// Convenience accessors that apply the override when present
    /// and defer to the shared settings snapshot otherwise. Callers
    /// should snapshot `SpeechSettings` at enqueue time (main actor)
    /// so the values don't shift mid-job.
    func effectiveVoice(fallback: String?) -> String? {
        voiceIdentifier ?? fallback
    }

    func effectiveRate(fallback: Double) -> Double {
        rate ?? fallback
    }

    func effectivePitch(fallback: Double) -> Double {
        pitchMultiplier ?? fallback
    }
}
