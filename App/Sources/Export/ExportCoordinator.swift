import Foundation
import AppKit
import Observation
import UniformTypeIdentifiers

/// Drives the export flow end-to-end: present an NSSavePanel,
/// run `AudioExporter.export`, surface progress and errors to UI
/// observers. Lives on the main actor.
@Observable
@MainActor
final class ExportCoordinator {
    enum State: Equatable {
        case idle
        case running(progress: Double)
        case succeeded(at: URL)
        case failed(message: String)
    }

    private(set) var state: State = .idle

    /// Present a save panel and, if accepted, kick off the export.
    /// Returns without waiting for the export itself; observers
    /// poll `state` for updates.
    func exportWithPrompt(
        sentences: [Sentence],
        suggestedName: String
    ) {
        guard !sentences.isEmpty else {
            state = .failed(message: "Load a document first.")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Audiobook"
        panel.nameFieldStringValue = suggestedName + ".m4a"
        panel.allowedContentTypes = [.mpeg4Audio]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        state = .running(progress: 0)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await AudioExporter.export(sentences: sentences, to: url) { fraction in
                    self.state = .running(progress: fraction)
                }
                self.state = .succeeded(at: url)
                // Reveal in Finder — polished UX touch.
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch let error as AudioExporter.ExportError {
                self.state = .failed(message: error.errorDescription ?? "Export failed.")
            } catch {
                self.state = .failed(message: error.localizedDescription)
            }
        }
    }

    func dismissAlert() {
        state = .idle
    }
}

