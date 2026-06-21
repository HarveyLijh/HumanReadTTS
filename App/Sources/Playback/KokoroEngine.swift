import Foundation
import os
import KokoroSwift
import MLX
import MLXUtilsLibrary

// `KokoroTTS` and `MLXArray` are reference-y types not formally
// `Sendable`. We initialise them once on a detached task and
// transfer the unique reference to the main actor — safe under
// region-isolation. Same pattern PDFDocumentLoader uses for
// `PDFDocument`.
extension KokoroTTS: @unchecked @retroactive Sendable {}
extension MLXArray: @unchecked @retroactive Sendable {}
// `KokoroSwift.Language` is a plain `String`-raw enum with no
// associated values. The upstream package hasn't declared it
// `Sendable`, so under Swift 6 strict concurrency we can't pass it
// across a `@Sendable` boundary without this retroactive conformance.
extension KokoroSwift.Language: @retroactive @unchecked Sendable {}

/// Non-`@MainActor` actor whose sole job is to run synthesis bodies
/// one-at-a-time on a cooperative thread. Ordering is FIFO per Swift
/// actor semantics, which is what we want: the main-path synth that
/// the user is listening to should play before any still-pending
/// prefetch that was kicked off for it.
private actor SynthGate {
    func run<T: Sendable>(_ body: @Sendable () throws -> T) async rethrows -> T {
        try body()
    }
}

/// Owns the loaded Kokoro TTS engine and its voice catalogue.
/// Loading is on-demand: nothing happens until either
/// `availableVoices` is asked for, or a synthesis call is made,
/// at which point we look at `ModelManager.shared` to see whether
/// the user has actually downloaded the model files.
@Observable
@MainActor
final class KokoroEngine {
    static let shared = KokoroEngine()

    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case failed(message: String)
    }

    private(set) var state: LoadState = .idle
    private(set) var voices: [VoiceInfo] = []

    struct VoiceInfo: Identifiable, Hashable, Sendable {
        /// The exposed identifier, prefixed `kokoro:` so it can't
        /// collide with `AVSpeechSynthesisVoice` identifiers in
        /// the voice picker.
        let id: String
        /// The canonical Kokoro voice id, e.g. `"af_heart"`.
        let kokoroID: String
        let displayName: String
        /// `true` for US English (Kokoro voice ids starting with
        /// `a`); `false` for British (`b`). Derived rather than
        /// stored as `KokoroSwift.Language` because that type
        /// isn't `Sendable`.
        let isUSEnglish: Bool
    }

    private var tts: KokoroTTS?
    private var voiceArrays: [String: MLXArray] = [:]

    /// Serializes every call into `KokoroTTS.generateAudio`.
    ///
    /// The underlying MisakiSwift `EnglishG2P` holds a single `NLTagger`
    /// and sets `tagger.string` then `tagger.setLanguage(range:)` in two
    /// non-atomic steps. Two concurrent `generateAudio` calls — e.g. the
    /// main-path synth for sentence N on the freshly-picked voice while
    /// the prefetch for N+1 on the old voice is still running — race on
    /// that tagger, and the second `setLanguage` sees a range computed
    /// from a string the tagger no longer holds. That trips a Swift
    /// string-range precondition and kills the app.
    private let gate = SynthGate()

    private static let log = Logger(subsystem: "app.readaloudtts.mac", category: "kokoro")

    private init() {}

    // MARK: MLX memory

    /// Cap for MLX's Metal buffer-reuse pool. MLX never returns freed
    /// intermediates (BERT/LSTM/prosody/iSTFT tensors) straight to the
    /// OS — it parks them in a reuse pool whose *default* ceiling is
    /// ~1.5× the device's recommended working-set size, i.e. tens of GB
    /// on a 32–64 GB Mac. Uncapped, the pool ratchets up to the
    /// worst-case synthesis working set and never shrinks, which shows
    /// up as a multi-GB resident footprint that never falls. A small
    /// reuse budget keeps the speed benefit while bounding the tail;
    /// the MLX maintainers note the perf cost of a low limit is minor.
    private static let mlxCacheLimitBytes = 512 * 1024 * 1024

    private static var didConfigureMLXMemory = false

    /// Bound the MLX cache once, before the first model load. Idempotent.
    private static func configureMLXMemoryOnce() {
        guard !didConfigureMLXMemory else { return }
        didConfigureMLXMemory = true
        let previous = MLX.Memory.cacheLimit
        MLX.Memory.cacheLimit = mlxCacheLimitBytes
        log.info("MLX cache limit set to \(mlxCacheLimitBytes / (1024 * 1024))MB (was \(previous / (1024 * 1024))MB)")
    }

    /// Immediately hand MLX's cached buffers back to the OS. The cache
    /// limit bounds growth but only takes effect on the next
    /// deallocation, so this forces an immediate drop — call it when
    /// playback stops so resident memory falls back toward the model's
    /// live working set. No-op unless the model is actually loaded
    /// (otherwise there is no MLX cache and we'd needlessly spin up
    /// Metal just to clear nothing).
    func releaseCache() {
        guard state == .ready else { return }
        MLX.Memory.clearCache()
        Self.logMemory("after clearCache")
    }

    /// Fully release the model so its ~650MB of weights leave resident
    /// memory — used when the user switches to a voice served by a
    /// different engine, so we don't keep Kokoro loaded for a session
    /// that's now on Qwen or a system voice. An in-flight synth holds
    /// its own captured `tts`/voice references, so dropping ours here
    /// is safe mid-stream; the model deallocates once that task ends.
    /// `clearCache()` then returns the freed buffers to the OS.
    func unload() {
        guard state == .ready else { return }
        tts = nil
        voiceArrays = [:]
        state = .idle
        MLX.Memory.clearCache()
        Self.logMemory("after unload")
    }

    /// Logs MLX's active (live weights + in-flight tensors) vs cached
    /// (reclaimable) resident memory. Lets us confirm the cap is
    /// holding and tell cache growth apart from a real leak.
    private static func logMemory(_ label: String) {
        let s = MLX.Memory.snapshot()
        let mb = { (bytes: Int) in bytes / (1024 * 1024) }
        log.info("MLX memory [\(label, privacy: .public)] active=\(mb(s.activeMemory))MB cache=\(mb(s.cacheMemory))MB peak=\(mb(s.peakMemory))MB")
    }

    /// Load the model + voices if the files are present on disk
    /// and we haven't loaded already. Cheap when state is already
    /// `.ready`. Run synchronously inside the async function but
    /// the heavy weight-loading runs on a detached task.
    func loadIfNeeded() async {
        switch state {
        case .ready, .loading: return
        default: break
        }

        let entry = ModelCatalog.kokoro
        guard ModelStorage.isInstalled(entry) else {
            state = .idle
            return
        }

        state = .loading
        Self.configureMLXMemoryOnce()
        Self.log.info("loading Kokoro model from \(ModelStorage.directory(for: entry).path, privacy: .public)")
        let started = ContinuousClock.now

        let modelPath = ModelStorage.directory(for: entry)
            .appending(path: "kokoro-v1_0.safetensors")
        let voicesPath = ModelStorage.directory(for: entry)
            .appending(path: "voices.npz")

        do {
            let result: (KokoroTTS, [String: MLXArray]) = try await Task.detached(priority: .userInitiated) {
                let tts = KokoroTTS(modelPath: modelPath, g2p: .misaki)
                guard let voices = NpyzReader.read(fileFromPath: voicesPath) else {
                    throw EngineError.voicesUnreadable
                }
                return (tts, voices)
            }.value

            tts = result.0
            voiceArrays = result.1
            voices = Self.makeVoiceCatalog(keys: result.1.keys)
            state = .ready

            let elapsed = ContinuousClock.now - started
            Self.log.info("Kokoro ready: \(self.voices.count) voices in \(elapsed, privacy: .public)")
            Self.logMemory("after load")
        } catch {
            state = .failed(message: error.localizedDescription)
            Self.log.error("Kokoro load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Synthesize `text` with the given voice. Returns 24 kHz mono
    /// PCM samples for the whole input as a single concatenated
    /// buffer. Used by prefetch and any caller that needs the
    /// complete audio in one piece.
    ///
    /// Long inputs are routed through `KokoroChunker` so that no
    /// single call into the underlying StyleTTS2 model exceeds the
    /// model's 510 phoneme-token ceiling (which would otherwise
    /// crash through to the system voice). For latency-sensitive
    /// foreground playback, prefer `synthesizeStream` — it yields
    /// each chunk as soon as it's ready, so the caller can start
    /// playing chunk 1 while chunk 2 is still being synthesised.
    func synthesize(text: String, voiceID: String, speed: Float = 1.0) async throws -> [Float] {
        var combined: [Float] = []
        var first = true
        let interChunkSilence = [Float](repeating: 0, count: KokoroChunker.interChunkSilenceFrames)
        for try await chunk in synthesizeStream(text: text, voiceID: voiceID, speed: speed) {
            if first {
                first = false
            } else {
                combined.append(contentsOf: interChunkSilence)
            }
            combined.append(contentsOf: chunk)
        }
        return combined
    }

    /// Streaming variant: yields each chunk's PCM samples as soon
    /// as it has been synthesised, so the caller can begin playback
    /// without waiting for the whole sentence. Short inputs yield
    /// exactly one chunk and finish; long inputs yield one chunk
    /// per `KokoroChunker` segment, in order.
    ///
    /// Errors (engine not ready, unknown voice, model failure) are
    /// surfaced through the stream's `finish(throwing:)` so the
    /// caller's `for try await` rethrows as expected.
    func synthesizeStream(
        text: String, voiceID: String, speed: Float = 1.0
    ) -> AsyncThrowingStream<[Float], Error> {
        AsyncThrowingStream { continuation in
            guard let tts else {
                continuation.finish(throwing: EngineError.notReady)
                return
            }
            let key = voiceID + ".npy"
            guard let voiceArray = voiceArrays[key] else {
                continuation.finish(throwing: EngineError.unknownVoice(voiceID))
                return
            }

            let language: KokoroSwift.Language = voiceID.hasPrefix("a") ? .enUS : .enGB
            let chunks = KokoroChunker.chunk(text)
            let bodies = chunks.isEmpty ? [text] : chunks

            if bodies.count > 1 {
                Self.log.info("Kokoro streaming long input (\(text.count) chars → \(bodies.count) chunks)")
            }

            let gate = self.gate
            let task = Task.detached(priority: .userInitiated) {
                do {
                    for chunkText in bodies {
                        try Task.checkCancellation()
                        let samples: [Float] = try await gate.run {
                            [tts, voiceArray, language, chunkText, speed] in
                            let (samples, _) = try tts.generateAudio(
                                voice: voiceArray,
                                language: language,
                                text: chunkText,
                                speed: speed
                            )
                            return samples
                        }
                        try Task.checkCancellation()
                        continuation.yield(samples)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Sample rate of the audio Kokoro returns.
    static let sampleRate: Double = 24_000

    enum EngineError: LocalizedError {
        case notReady
        case voicesUnreadable
        case unknownVoice(String)

        var errorDescription: String? {
            switch self {
            case .notReady: return "Kokoro is not loaded yet."
            case .voicesUnreadable: return "Couldn't read the voices.npz bundle."
            case .unknownVoice(let id): return "Unknown Kokoro voice '\(id)'."
            }
        }
    }

    // MARK: voice catalogue

    /// Translates the `.npy` keys in `voices.npz` into nicely
    /// named `VoiceInfo`s. Naming convention from the Kokoro
    /// project: first character indicates the variant
    /// (`a` = American, `b` = British, etc.) and the second
    /// indicates gender (`f` = female, `m` = male). The remainder
    /// is a free-form name (`heart`, `bella`, `alex`, etc.).
    private static func makeVoiceCatalog<K: Sequence>(keys: K) -> [VoiceInfo] where K.Element == String {
        keys
            .map { $0.replacingOccurrences(of: ".npy", with: "") }
            .compactMap { id -> VoiceInfo? in
                guard !id.isEmpty else { return nil }
                let isUS = id.first == "a"
                let langLabel = isUS ? "US English" : "British English"
                let name = id
                    .split(separator: "_", maxSplits: 1)
                    .last
                    .map { $0.split(separator: "_").joined(separator: " ").capitalized }
                    ?? id
                return VoiceInfo(
                    id: "kokoro:" + id,
                    kokoroID: id,
                    displayName: "\(name) (\(langLabel))",
                    isUSEnglish: isUS
                )
            }
            .sorted { $0.displayName < $1.displayName }
    }
}
