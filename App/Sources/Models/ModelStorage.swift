import Foundation

/// On-disk layout for downloaded models.
///
///   ~/Library/Application Support/ReadAloudTTS/models/
///     ├─ kokoro-82m-mlx/
///     │    ├─ config.json
///     │    ├─ kokoro-v0_19.safetensors
///     │    └─ .installed     ← presence == fully installed
///     └─ qwen3-tts-0.6b/
///          └─ ...
///
/// The `.installed` marker only gets written after every file in
/// the model's manifest has landed on disk. A partial download
/// (network drop mid-stream, app quit) is detectable as "directory
/// present but no marker."
enum ModelStorage {
    static let modelsDirectoryName = "ReadAloudTTS/models"
    static let installedMarker = ".installed"

    static var modelsDirectory: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(filePath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return base.appending(path: modelsDirectoryName, directoryHint: .isDirectory)
    }

    static func directory(for entry: ModelEntry) -> URL {
        modelsDirectory.appending(path: entry.id, directoryHint: .isDirectory)
    }

    static func ensureExists() throws {
        try FileManager.default.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )
    }

    static func ensureExists(for entry: ModelEntry) throws {
        try FileManager.default.createDirectory(
            at: directory(for: entry),
            withIntermediateDirectories: true
        )
    }

    static func isInstalled(_ entry: ModelEntry) -> Bool {
        let marker = directory(for: entry).appending(path: installedMarker)
        return FileManager.default.fileExists(atPath: marker.path)
    }

    static func markInstalled(_ entry: ModelEntry) throws {
        let marker = directory(for: entry).appending(path: installedMarker)
        try Data().write(to: marker)
    }

    /// Total bytes occupied on disk by this model's directory,
    /// or 0 if the directory does not exist.
    static func sizeOnDisk(_ entry: ModelEntry) -> Int64 {
        let dir = directory(for: entry)
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true,
                  let size = values?.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    static func delete(_ entry: ModelEntry) throws {
        let dir = directory(for: entry)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        try FileManager.default.removeItem(at: dir)
    }
}
