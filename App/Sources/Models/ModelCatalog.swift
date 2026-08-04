import Foundation

/// The curated set of models HumanReadTTS knows how to manage. Adding a
/// new model is a code change — by design, so the user doesn't
/// paste arbitrary URLs into Settings.
///
/// The Kokoro file URLs below point at the canonical
/// `mlalma/KokoroTestApp` repository (the integration project for
/// the same author's `kokoro-ios` Swift package). Files are
/// stored via Git LFS so the URLs use the `media.githubusercontent.com`
/// LFS redirect host rather than the regular `raw` host.
enum ModelCatalog {
    static let all: [ModelEntry] = [kokoro, qwen3TTSSmall, whisperBase]

    static let kokoro = ModelEntry(
        id: "kokoro-v1_0",
        displayName: "Kokoro v1.0 (English)",
        summary: "Studio-quality on-device English voice with 28 voice styles. Runs entirely locally via MLX.",
        kind: .ttsEnglish,
        approximateSizeMB: 650,
        files: kokoroFiles,
        engineIntegrated: true,
        upstreamURL: URL(string: "https://github.com/mlalma/kokoro-ios"),
        fetchStrategy: .manifest
    )

    /// Qwen3-TTS 0.6B via argmaxinc/WhisperKit's TTSKit product.
    /// Bilingual English + Chinese (plus eight other languages) with
    /// on-device MLX inference. TTSKit manages its own HuggingFace
    /// download flow, so the manifest is empty and the download
    /// path is `.ttsKit`.
    static let qwen3TTSSmall = ModelEntry(
        id: "qwen3-tts-0_6b",
        displayName: "Qwen3-TTS 0.6B (Bilingual)",
        summary: "Bilingual English / Chinese neural voice with six speaker styles. Runs via TTSKit on Apple Silicon.",
        kind: .ttsBilingual,
        approximateSizeMB: 1024,
        files: [],
        engineIntegrated: true,
        upstreamURL: URL(string: "https://github.com/argmaxinc/WhisperKit"),
        fetchStrategy: .ttsKit
    )

    /// Whisper-base via WhisperKit, used as a forced-alignment
    /// oracle for Kokoro/Qwen word-level highlight timings.
    /// ~145 MB on disk after WhisperKit's compile step.
    static let whisperBase = ModelEntry(
        id: "whisper-base",
        displayName: "Whisper Base (Alignment)",
        summary: "Optional: aligns neural TTS audio to word-level timings so the highlight follows individual words.",
        kind: .alignment,
        approximateSizeMB: 145,
        files: [],
        engineIntegrated: true,
        upstreamURL: URL(string: "https://github.com/argmaxinc/WhisperKit"),
        fetchStrategy: .whisperKit
    )

    // Two different hosts because one file is LFS-tracked and the
    // other isn't: the 600 MB safetensors model has to go through
    // the Git LFS media redirect, but the 14 MB voices.npz is
    // below GitHub's inline-blob threshold and served directly by
    // raw.githubusercontent.com. Verified with the
    // ModelCatalogReachabilityTests HEAD-request suite.
    private static let kokoroModelURL = URL(string:
        "https://media.githubusercontent.com/media/mlalma/KokoroTestApp/main/Resources/kokoro-v1_0.safetensors"
    )!
    private static let kokoroVoicesURL = URL(string:
        "https://raw.githubusercontent.com/mlalma/KokoroTestApp/main/Resources/voices.npz"
    )!

    private static let kokoroFiles: [ModelFile] = [
        ModelFile(relativePath: "kokoro-v1_0.safetensors", downloadURL: kokoroModelURL),
        ModelFile(relativePath: "voices.npz", downloadURL: kokoroVoicesURL),
    ]
}
