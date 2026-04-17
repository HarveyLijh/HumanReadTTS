import Foundation

/// The curated set of models Rhea knows how to manage. Adding a
/// new model is a code change — by design, so the user doesn't
/// paste arbitrary URLs into Settings.
///
/// The Kokoro file URLs below point at the public mlx-community
/// MLX port on Hugging Face. They're best-effort guesses based on
/// common HF layout conventions and will need verification once
/// the engine wiring lands in a follow-up. If a URL 404s the
/// download will fail loudly in the Models tab; replace it here
/// and rebuild.
enum ModelCatalog {
    static let all: [ModelEntry] = [
        ModelEntry(
            id: "kokoro-82m-mlx",
            displayName: "Kokoro 82M (English)",
            summary: "Studio-quality on-device English voice. Runs entirely locally via MLX.",
            kind: .ttsEnglish,
            approximateSizeMB: 165,
            files: kokoroFiles,
            engineIntegrated: false,
            upstreamURL: URL(string: "https://github.com/mlalma/kokoro-ios")
        )
    ]

    private static let kokoroBase = "https://huggingface.co/mlx-community/Kokoro-82M-bf16/resolve/main"

    private static let kokoroFiles: [ModelFile] = [
        ModelFile(
            relativePath: "config.json",
            downloadURL: URL(string: "\(kokoroBase)/config.json")!
        ),
        ModelFile(
            relativePath: "kokoro-v0_19.safetensors",
            downloadURL: URL(string: "\(kokoroBase)/kokoro-v0_19.safetensors")!
        )
    ]
}
