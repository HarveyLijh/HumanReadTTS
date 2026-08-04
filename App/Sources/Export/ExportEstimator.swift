import Foundation

/// Predicts how long an entire-article export will take based on
/// the chosen voice engine and total character count, with the
/// ability to self-correct from real export wall-clock times.
///
/// Why char-count, not sentence-count: sentence length varies
/// enormously between papers (long-form) and chat logs (one-liners),
/// so seconds-per-sentence drifts by an order of magnitude. Neural
/// TTS throughput correlates much more tightly with character count.
///
/// Defaults are M-series ballpark numbers — deliberately on the
/// conservative (slightly pessimistic) side so the first-run preview
/// reads as "about this long, maybe a bit less" rather than surprising
/// the user with longer-than-advertised waits. After the first real
/// export, `recordObservation(...)` blends the measured rate into a
/// per-engine rolling average, and subsequent previews use that.
@MainActor
enum ExportEstimator {
    /// Seconds of wall-clock synthesis per source character, per
    /// engine. Numbers assume warm model load — the first export
    /// after launch can be a bit slower; we accept that error in
    /// exchange for a stable preview.
    private static let defaultRates: [String: Double] = [
        "kokoro": 0.015,
        "qwen": 0.10,
        "system": 0.012,
    ]

    private static let storageKey = "app.humanreadtts.mac.export.secPerChar.v1"
    /// Weight of a fresh observation when blending into the rolling
    /// average. Low enough that a one-off slow export (swap pressure,
    /// another app hogging the Neural Engine) doesn't poison the
    /// estimate; high enough that the number converges within a few
    /// runs.
    private static let blendWeight: Double = 0.3

    /// Expected wall-clock seconds for synthesizing `sentences` via
    /// the chosen voice. Rate is accepted but deliberately *not*
    /// applied to neural engines — neural compute cost is roughly
    /// independent of playback speed, only the audio length changes.
    /// System voices' real-time synth does scale with rate, so we
    /// fold rate in only for that engine path.
    static func estimate(
        sentences: [Sentence],
        voiceIdentifier: String?,
        rate: Double
    ) -> TimeInterval {
        let chars = sentences.reduce(0) { $0 + $1.text.count }
        guard chars > 0 else { return 0 }
        let engine = engineKey(for: voiceIdentifier)
        let secPerChar = measuredRate(engine: engine) ?? defaultRates[engine] ?? 0.02
        let base = Double(chars) * secPerChar
        if engine == "system", rate > 0 {
            return base / rate
        }
        return base
    }

    /// Feed a real export's wall-clock cost back into the rolling
    /// average so future previews tighten up for this user's
    /// machine. EMA with weight `blendWeight` on the fresh sample.
    static func recordObservation(
        sentences: [Sentence],
        voiceIdentifier: String?,
        elapsed: TimeInterval
    ) {
        let chars = sentences.reduce(0) { $0 + $1.text.count }
        guard chars > 0, elapsed > 0 else { return }
        let engine = engineKey(for: voiceIdentifier)
        let fresh = elapsed / Double(chars)
        let existing = measuredRate(engine: engine) ?? defaultRates[engine] ?? fresh
        let blended = existing * (1 - blendWeight) + fresh * blendWeight
        var map = (UserDefaults.standard.dictionary(forKey: storageKey)
            as? [String: Double]) ?? [:]
        map[engine] = blended
        UserDefaults.standard.set(map, forKey: storageKey)
    }

    /// Human-readable "about Xm Ys" / "about Xs" string for the
    /// panel's ETA row. Rounds to whole seconds so the preview
    /// doesn't flicker on small state changes.
    static func formatted(_ seconds: TimeInterval) -> String {
        let total = max(1, Int(seconds.rounded()))
        if total < 60 {
            return "~\(total) sec"
        }
        let m = total / 60
        let s = total % 60
        if s == 0 {
            return "~\(m) min"
        }
        return "~\(m) min \(s) sec"
    }

    /// `true` when we're still using the baseline default (no real
    /// observation recorded yet). The sheet uses this to append a
    /// "(estimate will improve after first export)" footnote so the
    /// user knows why the number is ballpark.
    static func isUsingDefault(voiceIdentifier: String?) -> Bool {
        measuredRate(engine: engineKey(for: voiceIdentifier)) == nil
    }

    private static func engineKey(for voice: String?) -> String {
        guard let v = voice else { return "system" }
        if v.hasPrefix("kokoro:") { return "kokoro" }
        if v.hasPrefix("qwen:") { return "qwen" }
        return "system"
    }

    private static func measuredRate(engine: String) -> Double? {
        (UserDefaults.standard.dictionary(forKey: storageKey)
            as? [String: Double])?[engine]
    }
}
