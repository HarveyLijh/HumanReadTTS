import Foundation
import Observation

/// Tracks per-model status across the app. Single shared instance
/// so the Models settings tab and the (eventual) `SpeechPlayer`
/// engine-routing logic see the same state without environment
/// plumbing — same pattern as `SpeechSettings.shared`.
@Observable
@MainActor
final class ModelManager {
    static let shared = ModelManager()

    enum Status: Equatable {
        case notDownloaded
        case downloading(filesCompleted: Int, filesTotal: Int)
        case ready(sizeOnDisk: Int64)
        case failed(message: String)
    }

    private(set) var statuses: [String: Status] = [:]

    private init() {
        refresh()
    }

    /// Re-reads the on-disk state. Call after any external change
    /// (deleting files in Finder, manually clearing
    /// Application Support, etc.).
    func refresh() {
        for entry in ModelCatalog.all {
            if ModelStorage.isInstalled(entry) {
                statuses[entry.id] = .ready(sizeOnDisk: ModelStorage.sizeOnDisk(entry))
            } else {
                statuses[entry.id] = .notDownloaded
            }
        }
    }

    /// Kick off a download for `entry`. Updates `statuses[entry.id]`
    /// as files complete; never throws — the caller observes
    /// `statuses` for the result.
    func download(_ entry: ModelEntry) async {
        statuses[entry.id] = .downloading(filesCompleted: 0, filesTotal: entry.files.count)

        do {
            try await ModelDownloader.install(entry) { [weak self] completed, total in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if completed < total {
                        self.statuses[entry.id] = .downloading(
                            filesCompleted: completed, filesTotal: total
                        )
                    }
                }
            }
            statuses[entry.id] = .ready(sizeOnDisk: ModelStorage.sizeOnDisk(entry))
        } catch let failure as ModelDownloader.Failure {
            statuses[entry.id] = .failed(message: failure.errorDescription ?? "Download failed.")
        } catch {
            statuses[entry.id] = .failed(message: error.localizedDescription)
        }
    }

    /// Remove a model from disk. Status returns to `.notDownloaded`.
    func delete(_ entry: ModelEntry) {
        do {
            try ModelStorage.delete(entry)
            statuses[entry.id] = .notDownloaded
        } catch {
            statuses[entry.id] = .failed(message: "Couldn't delete: \(error.localizedDescription)")
        }
    }

    /// True when this model is installed and the engine that uses
    /// it is also wired in. Used by future engine-routing in
    /// `SpeechPlayer` to decide whether to send English text to
    /// Kokoro vs. AVSpeechSynthesizer.
    func isUsable(_ entry: ModelEntry) -> Bool {
        guard entry.engineIntegrated else { return false }
        if case .ready = statuses[entry.id] { return true }
        return false
    }
}
