import Foundation
import os
import WhisperKit

// WhisperKit's main pipeline isn't formally Sendable, but we use it
// from a single actor and transfer results by value. Same pattern
// as the Kokoro extensions above.
extension WhisperKit: @unchecked @retroactive Sendable {}

/// Optional forced-alignment oracle for the neural TTS paths.
/// Kokoro and Qwen3-TTS both produce a PCM buffer with no built-in
/// word timings. We run the same audio through WhisperKit with
/// word timestamps enabled, then splice Whisper's per-word timings
/// onto our *known* text to drive the character-range highlight.
///
/// This is approximate forced alignment — Whisper's transcription
/// of clean TTS audio matches the source text closely but not
/// perfectly. Good enough for sub-sentence highlight on clean
/// synthesised speech; the mapping step stays resilient to small
/// word-count mismatches by doing a greedy substring scan.
@Observable
@MainActor
final class WhisperAligner {
    static let shared = WhisperAligner()

    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case failed(message: String)
    }

    private(set) var state: LoadState = .idle
    private var pipeline: WhisperKit?

    /// A single word's timing against the known sentence. The
    /// `characterRange` is an NSRange into the sentence text; the
    /// times are seconds from the start of the synthesised clip.
    struct AlignedWord: Sendable, Hashable {
        let characterRange: NSRange
        let startSeconds: Double
        let endSeconds: Double
    }

    private static let log = Logger(subsystem: "app.rhea.mac", category: "whisper")

    private init() {}

    /// Load the Whisper model from our ModelStorage directory if
    /// we haven't already. Safe to call repeatedly.
    func loadIfNeeded() async {
        switch state {
        case .ready, .loading: return
        default: break
        }

        let entry = ModelCatalog.whisperBase
        guard ModelStorage.isInstalled(entry) else {
            state = .idle
            return
        }

        state = .loading
        let modelFolder = ModelStorage.directory(for: entry)
        Self.log.info("loading Whisper base from \(modelFolder.path, privacy: .public)")

        do {
            let config = WhisperKitConfig(
                modelFolder: modelFolder.path,
                verbose: false,
                prewarm: true,
                load: true,
                download: false
            )
            pipeline = try await WhisperKit(config)
            state = .ready
        } catch {
            state = .failed(message: error.localizedDescription)
            Self.log.error("Whisper load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Align `samples` (mono Float32 PCM at any common rate) to the
    /// known `text`. Returns per-word timings against the sentence,
    /// or nil if the aligner isn't loaded or the transcription
    /// failed.
    func align(samples: [Float], text: String, sampleRate: Double) async -> [AlignedWord]? {
        await loadIfNeeded()
        guard state == .ready, let pipeline else { return nil }

        // WhisperKit expects 16 kHz mono Float32. Resample if needed.
        let prepared = Self.resampleTo16k(samples, from: sampleRate)

        do {
            let options = DecodingOptions(
                verbose: false,
                task: .transcribe,
                withoutTimestamps: false,
                wordTimestamps: true
            )
            let results = try await Task.detached(priority: .userInitiated) { [pipeline] in
                try await pipeline.transcribe(
                    audioArray: prepared,
                    decodeOptions: options
                )
            }.value
            let words = results.flatMap {
                $0.segments.flatMap { $0.words ?? [] }
            }
            return Self.mapWordsToText(words, text: text)
        } catch {
            Self.log.error("Whisper align failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: helpers

    private static func resampleTo16k(_ samples: [Float], from rate: Double) -> [Float] {
        let target: Double = 16_000
        if abs(rate - target) < 0.5 { return samples }
        let ratio = target / rate
        let outCount = Int((Double(samples.count) * ratio).rounded())
        var out = [Float](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let srcIdx = Int((Double(i) / ratio).rounded())
            out[i] = samples[min(srcIdx, samples.count - 1)]
        }
        return out
    }

    /// Map Whisper's per-word timings onto our known sentence
    /// text. Uses a greedy left-to-right scan: for each Whisper
    /// word, find its next occurrence (case-insensitive, diacritic-
    /// insensitive) in the remaining sentence substring and record
    /// the character range. Gracefully skips over Whisper
    /// hallucinations by treating "no match" as "drop this word."
    private static func mapWordsToText(
        _ whisperWords: [WordTiming],
        text: String
    ) -> [AlignedWord] {
        let nsText = text as NSString
        var cursor = 0
        var result: [AlignedWord] = []
        let ws = CharacterSet.whitespacesAndNewlines
        for wt in whisperWords {
            let needle = wt.word.trimmingCharacters(in: ws)
            guard !needle.isEmpty else { continue }
            let range = nsText.range(
                of: needle,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: NSRange(location: cursor, length: nsText.length - cursor)
            )
            guard range.location != NSNotFound else { continue }
            result.append(AlignedWord(
                characterRange: range,
                startSeconds: Double(wt.start),
                endSeconds: Double(wt.end)
            ))
            cursor = range.location + range.length
        }
        return result
    }
}
