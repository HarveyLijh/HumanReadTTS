import Foundation

/// The curated set of models Rhea knows how to manage. Adding a
/// new model is a code change — by design, so the user doesn't
/// paste arbitrary URLs into Settings.
///
/// The Kokoro file URLs below point at the canonical
/// `mlalma/KokoroTestApp` repository (the integration project for
/// the same author's `kokoro-ios` Swift package). Files are
/// stored via Git LFS so the URLs use the `media.githubusercontent.com`
/// LFS redirect host rather than the regular `raw` host.
enum ModelCatalog {
    static let all: [ModelEntry] = [kokoro]

    static let kokoro = ModelEntry(
        id: "kokoro-v1_0",
        displayName: "Kokoro v1.0 (English)",
        summary: "Studio-quality on-device English voice with 28 voice styles. Runs entirely locally via MLX.",
        kind: .ttsEnglish,
        approximateSizeMB: 650,
        files: kokoroFiles,
        engineIntegrated: true,
        upstreamURL: URL(string: "https://github.com/mlalma/kokoro-ios")
    )

    private static let kokoroBase = "https://media.githubusercontent.com/media/mlalma/KokoroTestApp/main/KokoroTestApp/Resources"

    private static let kokoroFiles: [ModelFile] = [
        ModelFile(
            relativePath: "kokoro-v1_0.safetensors",
            downloadURL: URL(string: "\(kokoroBase)/kokoro-v1_0.safetensors")!
        ),
        ModelFile(
            relativePath: "voices.npz",
            downloadURL: URL(string: "\(kokoroBase)/voices.npz")!
        )
    ]
}
