import Foundation

/// A single downloadable on-device model. Right now this only
/// covers the neural TTS family (Kokoro for English, Qwen3-TTS for
/// Chinese / bilingual in M3.1, optional WhisperKit alignment for
/// M2.3 word-level highlighting). The catalog is intentionally
/// curated — the user does not pick arbitrary URLs.
struct ModelEntry: Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case ttsEnglish
        case ttsBilingual
        case alignment
    }

    /// Stable identifier used both as the on-disk directory name
    /// and as a key in `ModelManager.statuses`. Treat as opaque;
    /// the catalog assigns these.
    let id: String

    /// Shown in the Models tab list.
    let displayName: String

    /// Short description shown under the title in the Models tab.
    let summary: String

    let kind: Kind

    /// Approximate on-disk size in MB. Shown in the UI so the user
    /// knows what they're committing to before tapping Download.
    let approximateSizeMB: Int

    /// Files that make up the model. All are downloaded to
    /// `<modelsDirectory>/<id>/<file.relativePath>`. The model is
    /// considered installed once every file is present and a
    /// `.installed` marker has been written.
    let files: [ModelFile]

    /// Engine integration status — separate from download status.
    /// `false` means: even if you download this, the playback path
    /// can't yet route through the corresponding engine. UI shows
    /// a footnote in that case so the user isn't surprised.
    let engineIntegrated: Bool

    /// Source URL of the upstream project for the user to inspect
    /// licensing and provenance.
    let upstreamURL: URL?
}

struct ModelFile: Hashable, Sendable {
    /// Relative path within the model directory (may contain
    /// subdirectories like "voices/af_heart.bin").
    let relativePath: String
    let downloadURL: URL
}
