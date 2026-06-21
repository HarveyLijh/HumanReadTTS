import Foundation
import AVFoundation
import os
import TTSKit

// `TTSKit` carries some `@unchecked Sendable` semantics internally;
// the returned `SpeechResult.audio` is an `AVAudioPCMBuffer`
// (already unchecked-Sendable via AudioExporter). Same pattern we
// use for Kokoro's `KokoroTTS` reference type.

/// Owns the loaded Qwen3-TTS engine. Unlocks bilingual EN+ZH
/// neural TTS (plus eight other languages) through a single on-
/// device MLX pipeline. Loading is on-demand: nothing happens
/// until the user picks a `qwen:` voice. Weights are downloaded
/// from Hugging Face into the shared ModelStorage directory on
/// first use, matching Kokoro's download-then-pick flow.
///
/// Voices are strings that the Qwen3-TTS model knows natively
/// (e.g. "Cherry", "Ethan", "Nofish"). Language is passed
/// explicitly per sentence — upstream `SpeechPlayer` detects the
/// language via `NLLanguageRecognizer` so a bilingual doc can
/// flip voice character without the user switching manually.
@Observable
@MainActor
final class QwenEngine {
    static let shared = QwenEngine()

    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case failed(message: String)
    }

    private(set) var state: LoadState = .idle
    private(set) var voices: [VoiceInfo] = []

    struct VoiceInfo: Identifiable, Hashable, Sendable {
        /// The exposed identifier, prefixed `qwen:` so it can't
        /// collide with `kokoro:` or `AVSpeechSynthesisVoice` ids.
        let id: String
        /// The canonical Qwen3-TTS speaker name.
        let qwenName: String
        let displayName: String
    }

    private var tts: TTSKit?

    /// Output rate Qwen3-TTS returns. Stays 24 kHz like Kokoro so
    /// `PCMAudioPlayer` can be reused.
    static let sampleRate: Double = 24_000

    private static let log = Logger(subsystem: "app.readaloudtts.mac", category: "qwen")

    private init() {
        voices = Self.makeVoiceCatalog()
    }

    /// Load the model if installed. No-op when state is already
    /// `.ready` or `.loading`. If the model hasn't been downloaded
    /// we leave state as `.idle` — the Settings → Models tab
    /// handles the download via `ModelManager`.
    func loadIfNeeded() async {
        switch state {
        case .ready, .loading: return
        default: break
        }

        let entry = ModelCatalog.qwen3TTSSmall
        guard ModelStorage.isInstalled(entry) else {
            state = .idle
            return
        }

        state = .loading
        let baseDir = ModelStorage.directory(for: entry)
        // TTSKit.download lands the HuggingFace tree at
        // `<base>/models/argmaxinc/ttskit-coreml/qwen3_tts/`, not at
        // `<base>/` directly. TTSKit(modelFolder:) expects the
        // flattened root containing `text_projector/`,
        // `speech_decoder/`, etc. Resolve whichever layout the
        // downloader produced.
        let modelFolder = Self.resolveModelFolder(inside: baseDir)
        Self.log.info("loading Qwen3-TTS from \(modelFolder.path, privacy: .public)")
        let started = ContinuousClock.now

        do {
            let engine = try await TTSKit(
                model: .qwen3TTS_0_6b,
                modelFolder: modelFolder,
                verbose: false,
                // prewarm runs an extra warm-up forward pass at load,
                // doubling the CoreML/ANE compilation of the large
                // code_decoder/text_projector graphs and inflating the
                // on-open memory peak. We trade a slightly slower first
                // sentence for a smaller spike; `load: true` still
                // materializes the weights so playback is ready.
                prewarm: false,
                load: true,
                download: false
            )
            tts = engine
            state = .ready
            let elapsed = ContinuousClock.now - started
            Self.log.info("Qwen3-TTS ready in \(elapsed, privacy: .public)")
        } catch {
            state = .failed(message: error.localizedDescription)
            Self.log.error("Qwen3-TTS load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Release the ~1GB of CoreML weights when the user switches to a
    /// voice served by a different engine. Voices stay listed (the
    /// catalog is static), so the picker still shows them; the model
    /// reloads lazily on the next Qwen synth.
    func unload() async {
        guard state == .ready else { return }
        await tts?.unloadModels()
        tts = nil
        state = .idle
        Self.log.info("Qwen3-TTS unloaded")
    }

    /// Synthesize `text` as 24 kHz mono PCM. `language` is an ISO
    /// code — "en", "zh", "ja", etc. Falls back to the model's
    /// default when nil.
    func synthesize(
        text: String,
        voiceID: String,
        language: String?,
        speed: Float = 1.0
    ) async throws -> [Float] {
        guard let tts else { throw EngineError.notReady }
        let result = try await tts.generate(
            text: text,
            voice: voiceID,
            language: language
        )
        return result.audio
    }

    enum EngineError: LocalizedError {
        case notReady

        var errorDescription: String? {
            switch self {
            case .notReady: return "Qwen3-TTS is not loaded yet."
            }
        }
    }

    /// Returns the directory TTSKit expects as `modelFolder`. TTSKit
    /// internally appends `qwen3_tts/<component>/<versionDir>/<variant>`
    /// to this path, so we need to point one level above `qwen3_tts/`.
    /// First checks `base/` itself (old flat layout); otherwise uses
    /// the nested HuggingFace path that TTSKit's downloader produces
    /// at `base/models/argmaxinc/ttskit-coreml/`.
    private static func resolveModelFolder(inside base: URL) -> URL {
        let fm = FileManager.default
        let marker = "qwen3_tts/text_projector"
        if fm.fileExists(atPath: base.appending(path: marker).path) {
            return base
        }
        let nested = base
            .appending(path: "models")
            .appending(path: "argmaxinc")
            .appending(path: "ttskit-coreml")
        if fm.fileExists(atPath: nested.appending(path: marker).path) {
            return nested
        }
        return base
    }

    // MARK: voice catalogue

    /// Qwen3-TTS ships with a small zoo of named speakers. We
    /// expose a curated, stable subset — enough for EN+ZH listening
    /// without overwhelming the voice picker. Display names note
    /// the intended feel so the user can pick by vibe rather than
    /// memorise the canonical Qwen name.
    private static func makeVoiceCatalog() -> [VoiceInfo] {
        let catalog: [(String, String)] = [
            ("Cherry",  "Cherry (warm, EN / ZH)"),
            ("Ethan",   "Ethan (steady male, EN / ZH)"),
            ("Nofish",  "Nofish (bright male, EN / ZH)"),
            ("Jennifer","Jennifer (clear female, EN / ZH)"),
            ("Ryan",    "Ryan (narrator male, EN / ZH)"),
            ("Katerina","Katerina (calm female, EN / ZH)"),
        ]
        return catalog.map { qwenName, display in
            VoiceInfo(
                id: "qwen:" + qwenName,
                qwenName: qwenName,
                displayName: display
            )
        }
    }
}
