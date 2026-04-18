import SwiftUI
import AppKit

/// Dedicated window scene listing every enqueued export job with
/// per-row progress, status, and "Show in Finder" / "Delete file"
/// actions. Opened via the File → Show Exports menu item
/// (or ⌘⇧J). The queue itself lives on the `ExportCoordinator`
/// shared between the transport and this view, so kicking off
/// another export from the main window and watching progress here
/// is the expected flow.
@MainActor
struct ExportQueueView: View {
    @Bindable var coordinator: ExportCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if coordinator.jobs.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(coordinator.jobs) { job in
                            jobRow(job)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 360)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Exports")
                .font(.headline)
            Text(statusSummary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear completed") {
                coordinator.clearCompleted()
            }
            .disabled(!hasCompletedJobs)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var statusSummary: String {
        let running = coordinator.jobs.filter {
            if case .running = $0.state { return true }
            return false
        }.count
        let queued = coordinator.jobs.filter {
            if case .queued = $0.state { return true }
            return false
        }.count
        if running > 0 || queued > 0 {
            return "\(running) running · \(queued) queued"
        }
        return "idle"
    }

    private var hasCompletedJobs: Bool {
        coordinator.jobs.contains { job in
            switch job.state {
            case .succeeded, .failed: return true
            case .queued, .running: return false
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text("No exports yet.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("Open a document and choose File → Export Audiobook… (⌘⇧E).")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func jobRow(_ job: ExportJob) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: iconName(for: job.state))
                    .foregroundStyle(iconTint(for: job.state))
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text(job.format.fileExtension.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                        Text("\(job.sentences.count) sentences")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(job.createdAt, format: .dateTime.hour().minute())
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                controls(for: job)
            }
            statusLine(for: job)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func statusLine(for job: ExportJob) -> some View {
        switch job.state {
        case .queued:
            Text("Waiting in queue")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .running(let fraction):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                Text(String(format: "%.0f%%", fraction * 100))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        case .succeeded(let url):
            Text(url.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        case .failed(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func controls(for job: ExportJob) -> some View {
        HStack(spacing: 4) {
            switch job.state {
            case .succeeded(let url):
                Button {
                    coordinator.revealInFinder(url)
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .failed:
                Button {
                    coordinator.removeJob(job.id)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .queued:
                Button {
                    coordinator.removeJob(job.id)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Remove from queue")
            case .running:
                ProgressView()
                    .controlSize(.mini)
            }
        }
    }

    private func iconName(for state: ExportJob.State) -> String {
        switch state {
        case .queued: return "hourglass"
        case .running: return "waveform"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func iconTint(for state: ExportJob.State) -> Color {
        switch state {
        case .queued: return .secondary
        case .running: return Color.rheaAccent
        case .succeeded: return .green
        case .failed: return .orange
        }
    }
}
