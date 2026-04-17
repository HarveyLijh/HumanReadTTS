import Foundation
import TTSKit
import WhisperKit

/// Downloads each file in a `ModelEntry`'s manifest to its slot
/// under `ModelStorage.directory(for:)`. Sequential per-file
/// downloads (no parallelism) so we can report a clean
/// files-completed / files-total progress.
///
/// Per-byte progress within a single file is intentionally not
/// reported in this first cut — `URLSession.shared.download(from:)`
/// already streams to disk and the UI just shows "downloading
/// file 1 of 2" until the whole model lands. Granular byte-level
/// progress requires a `URLSessionDownloadDelegate`, which is a
/// follow-up if the larger files need it.
enum ModelDownloader {
    enum Failure: LocalizedError {
        case http(status: Int, url: URL)
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .http(let status, let url):
                return "Server returned \(status) for \(url.lastPathComponent)."
            case .underlying(let error):
                return error.localizedDescription
            }
        }
    }

    /// Download every file in the model's manifest and write the
    /// `.installed` marker on success. Raises on the first failure;
    /// any partial download is left in place so the user can see
    /// "directory present, marker absent" and choose to retry.
    static func install(
        _ entry: ModelEntry,
        progress: (@Sendable (_ filesCompleted: Int, _ filesTotal: Int) -> Void)? = nil
    ) async throws {
        try ModelStorage.ensureExists(for: entry)

        switch entry.fetchStrategy {
        case .manifest:
            try await installFromManifest(entry, progress: progress)
        case .ttsKit:
            try await installFromTTSKit(entry, progress: progress)
        case .whisperKit:
            try await installFromWhisperKit(entry, progress: progress)
        }

        try ModelStorage.markInstalled(entry)
    }

    private static func installFromManifest(
        _ entry: ModelEntry,
        progress: (@Sendable (Int, Int) -> Void)?
    ) async throws {
        let total = entry.files.count
        for (index, file) in entry.files.enumerated() {
            progress?(index, total)
            try await fetch(file, into: ModelStorage.directory(for: entry))
        }
        progress?(total, total)
    }

    /// TTSKit owns its own HuggingFace-aware downloader. We anchor
    /// the target into our own models directory so the Settings →
    /// Models tab's size-on-disk + delete flow still works.
    private static func installFromTTSKit(
        _ entry: ModelEntry,
        progress: (@Sendable (Int, Int) -> Void)?
    ) async throws {
        progress?(0, 1)
        let dir = ModelStorage.directory(for: entry)
        _ = try await TTSKit.download(
            variant: .qwen3TTS_0_6b,
            downloadBase: dir,
            useBackgroundSession: false
        )
        progress?(1, 1)
    }

    /// WhisperKit's `download` fetches a specific model bundle and
    /// returns the folder URL. We redirect it at our storage dir so
    /// install/delete is symmetric with the other entries.
    private static func installFromWhisperKit(
        _ entry: ModelEntry,
        progress: (@Sendable (Int, Int) -> Void)?
    ) async throws {
        progress?(0, 1)
        let dir = ModelStorage.directory(for: entry)
        _ = try await WhisperKit.download(
            variant: "base",
            downloadBase: dir,
            useBackgroundSession: false,
            from: "argmaxinc/whisperkit-coreml"
        )
        progress?(1, 1)
    }

    private static func fetch(_ file: ModelFile, into directory: URL) async throws {
        let destination = directory.appending(path: file.relativePath)

        // Ensure the destination's parent directory exists (model
        // files may live in nested subdirectories like voices/).
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent, withIntermediateDirectories: true
        )

        let (tempURL, response) = try await URLSession.shared.download(from: file.downloadURL)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            try? FileManager.default.removeItem(at: tempURL)
            throw Failure.http(status: http.statusCode, url: file.downloadURL)
        }

        // Replace any existing file (re-download case).
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }
}
