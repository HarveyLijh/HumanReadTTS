import Foundation
import AppKit
import Observation
import UniformTypeIdentifiers
import os

/// A single export job the queue tracks. Captured at enqueue time
/// so later edits to the document (loading a new file, changing
/// voice) don't retroactively affect in-flight work.
struct ExportJob: Identifiable, Equatable {
    enum State: Equatable {
        case queued
        case running(progress: Double)
        case succeeded(at: URL)
        case failed(message: String)
    }

    let id: UUID
    let title: String
    let createdAt: Date
    let sentences: [Sentence]
    let destination: URL
    let format: AudioExportFormat
    /// Per-job voice/rate/pitch overrides set by the dedicated
    /// "Generate Audio…" panel. Empty/`.none` means "use the live
    /// SpeechSettings at synth time", matching the original
    /// File → Export Audiobook flow.
    let overrides: ExportOverrides
    var state: State

    init(
        id: UUID = UUID(),
        title: String,
        sentences: [Sentence],
        destination: URL,
        format: AudioExportFormat,
        overrides: ExportOverrides = .none
    ) {
        self.id = id
        self.title = title
        self.createdAt = Date()
        self.sentences = sentences
        self.destination = destination
        self.format = format
        self.overrides = overrides
        self.state = .queued
    }
}

/// Single-concurrency export queue. Multiple enqueues run one at a
/// time — neural TTS is already saturating the CPU/Neural Engine
/// per sentence, so parallel jobs would just thrash. Lives on the
/// main actor so SwiftUI can observe `jobs` directly.
///
/// Backward-compat: `ExportCoordinator.exportWithPrompt` still
/// works and now routes through the queue, so existing menu / HUD
/// code doesn't need to change immediately. `state` still reports
/// the *most recent* job for banners that only show one status at
/// a time.
@Observable
@MainActor
final class ExportCoordinator {
    /// Shared instance so the main window's export triggers and the
    /// separate Exports window observe the same queue. A new window
    /// per export would split state across scenes; readers expect
    /// "show me what's running" to reflect everything.
    static let shared = ExportCoordinator()

    private(set) var jobs: [ExportJob] = []
    private(set) var state: State = .idle

    enum State: Equatable {
        case idle
        case running(progress: Double)
        case succeeded(at: URL)
        case failed(message: String)
    }

    private var isProcessing = false
    private static let log = Logger(subsystem: "app.rhea.mac", category: "export")

    /// Present a save panel (with format picker) and, if accepted,
    /// enqueue the job. Returns immediately; progress is observable
    /// on `jobs` and on `state`.
    func exportWithPrompt(
        sentences: [Sentence],
        suggestedName: String
    ) {
        guard !sentences.isEmpty else {
            state = .failed(message: "Load a document first.")
            return
        }

        var chosenFormat: AudioExportFormat = .m4a

        let panel = NSSavePanel()
        panel.title = "Export Audiobook"
        panel.nameFieldStringValue = suggestedName + "." + chosenFormat.fileExtension
        panel.allowedContentTypes = AudioExportFormat.allCases.map(\.contentType)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        // Attach a format picker to the save panel so the user
        // decides once, at export time, instead of hunting through
        // Settings. Ties the filename extension to the choice so
        // the extension stays honest.
        let accessory = AudioFormatAccessoryView(initial: .m4a) { format in
            chosenFormat = format
            let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = base + "." + format.fileExtension
        }
        panel.accessoryView = accessory.hostingView

        let response = panel.runModal()
        guard response == .OK, var url = panel.url else { return }

        // The user may have typed a different extension than the
        // picker's selection. Normalise so the extension matches.
        if url.pathExtension.lowercased() != chosenFormat.fileExtension {
            url.deletePathExtension()
            url.appendPathExtension(chosenFormat.fileExtension)
        }

        enqueue(
            sentences: sentences,
            destination: url,
            format: chosenFormat,
            title: suggestedName
        )
    }

    /// Direct enqueue — used by the Exports panel's "re-run" flow
    /// and by callers that have already picked a destination.
    func enqueue(
        sentences: [Sentence],
        destination: URL,
        format: AudioExportFormat,
        title: String,
        overrides: ExportOverrides = .none
    ) {
        let job = ExportJob(
            title: title,
            sentences: sentences,
            destination: destination,
            format: format,
            overrides: overrides
        )
        jobs.append(job)
        kickProcessing()
    }

    /// Remove a finished job from the queue display. Running jobs
    /// stay put — the user has to wait for completion or quit the
    /// app. Partial files aren't cleaned up on app quit; leftovers
    /// are on disk at the destination the user picked.
    func removeJob(_ id: UUID) {
        jobs.removeAll { job in
            guard job.id == id else { return false }
            // Don't remove a running job out from under the worker.
            if case .running = job.state { return false }
            return true
        }
    }

    func clearCompleted() {
        jobs.removeAll { job in
            switch job.state {
            case .succeeded, .failed: return true
            case .queued, .running: return false
            }
        }
    }

    func dismissAlert() {
        state = .idle
    }

    /// Reveal the finished file in Finder. Callers typically wire
    /// this to the per-row "Show in Finder" button.
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: queue worker

    private func kickProcessing() {
        guard !isProcessing else { return }
        isProcessing = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.processQueue()
            self.isProcessing = false
        }
    }

    private func processQueue() async {
        while let nextIdx = jobs.firstIndex(where: {
            if case .queued = $0.state { return true }
            return false
        }) {
            jobs[nextIdx].state = .running(progress: 0)
            state = .running(progress: 0)
            let job = jobs[nextIdx]
            Self.log.info("starting job \(job.id, privacy: .public) → \(job.destination.path, privacy: .public)")

            let started = ContinuousClock.now
            do {
                try await AudioExporter.export(
                    sentences: job.sentences,
                    to: job.destination,
                    format: job.format,
                    overrides: job.overrides
                ) { [weak self] fraction in
                    guard let self else { return }
                    if let idx = self.jobs.firstIndex(where: { $0.id == job.id }) {
                        self.jobs[idx].state = .running(progress: fraction)
                    }
                    self.state = .running(progress: fraction)
                }
                if let idx = jobs.firstIndex(where: { $0.id == job.id }) {
                    jobs[idx].state = .succeeded(at: job.destination)
                }
                state = .succeeded(at: job.destination)
                // Feed real elapsed wall-clock back into the
                // estimator so future ETA previews tighten up for
                // this machine + engine combination.
                let elapsed = ContinuousClock.now - started
                let resolvedVoice = job.overrides.effectiveVoice(
                    fallback: SpeechSettings.shared.voiceIdentifier
                )
                ExportEstimator.recordObservation(
                    sentences: job.sentences,
                    voiceIdentifier: resolvedVoice,
                    elapsed: TimeInterval(elapsed.components.seconds)
                        + Double(elapsed.components.attoseconds) / 1e18
                )
                NSWorkspace.shared.activateFileViewerSelecting([job.destination])
            } catch let error as AudioExporter.ExportError {
                let msg = error.errorDescription ?? "Export failed."
                if let idx = jobs.firstIndex(where: { $0.id == job.id }) {
                    jobs[idx].state = .failed(message: msg)
                }
                state = .failed(message: msg)
            } catch {
                let msg = error.localizedDescription
                if let idx = jobs.firstIndex(where: { $0.id == job.id }) {
                    jobs[idx].state = .failed(message: msg)
                }
                state = .failed(message: msg)
            }
        }
    }
}

// MARK: - NSSavePanel accessory view

/// Hosts a SwiftUI picker inside the AppKit save panel's accessory
/// slot. The panel is modal AppKit; a lightweight NSHostingView
/// bridges SwiftUI content in without pulling in the window scene.
@MainActor
private final class AudioFormatAccessoryView {
    let hostingView: NSView
    private let onChange: (AudioExportFormat) -> Void

    init(
        initial: AudioExportFormat,
        onChange: @escaping (AudioExportFormat) -> Void
    ) {
        self.onChange = onChange
        let picker = AudioFormatPicker(selection: initial, onChange: onChange)
        let host = NSHostingView(rootView: picker)
        host.frame = NSRect(x: 0, y: 0, width: 440, height: 52)
        self.hostingView = host
    }
}

import SwiftUI

private struct AudioFormatPicker: View {
    @State private var selection: AudioExportFormat
    let onChange: (AudioExportFormat) -> Void

    init(
        selection: AudioExportFormat,
        onChange: @escaping (AudioExportFormat) -> Void
    ) {
        self._selection = State(initialValue: selection)
        self.onChange = onChange
    }

    var body: some View {
        HStack {
            Text("Format:")
            Picker("", selection: $selection) {
                ForEach(AudioExportFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .labelsHidden()
            .onChange(of: selection) { _, new in
                onChange(new)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
