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

    private static let log = Logger(subsystem: "app.rhea.mac", category: "kokoro")

    private init() {}

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
        } catch {
            state = .failed(message: error.localizedDescription)
            Self.log.error("Kokoro load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Synthesize `text` with the given voice. Returns 24 kHz mono
    /// PCM samples. Throws if the engine isn't loaded or the voice
    /// is unknown.
    func synthesize(text: String, voiceID: String, speed: Float = 1.0) async throws -> [Float] {
        guard let tts else { throw EngineError.notReady }
        let key = voiceID + ".npy"
        guard let voiceArray = voiceArrays[key] else {
            throw EngineError.unknownVoice(voiceID)
        }

        let language: KokoroSwift.Language = voiceID.hasPrefix("a") ? .enUS : .enGB

        let samples: [Float] = try await Task.detached(priority: .userInitiated) {
            let (samples, _) = try tts.generateAudio(
                voice: voiceArray,
                language: language,
                text: text,
                speed: speed
            )
            return samples
        }.value

        return samples
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
