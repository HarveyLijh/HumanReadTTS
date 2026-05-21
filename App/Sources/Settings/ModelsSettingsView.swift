import SwiftUI

/// The Models tab in Settings. Lists every entry in
/// `ModelCatalog.all` with its current status and the appropriate
/// action — Download, cancel-during-download (deferred), Remove,
/// or Retry on failure.
///
/// Models flagged as `engineIntegrated == false` show a
/// "engine pending" footnote so the user doesn't download a 165 MB
/// file expecting playback to immediately route through it.
struct ModelsSettingsView: View {
    @Bindable var manager: ModelManager = .shared

    var body: some View {
        Form {
            ForEach(ModelCatalog.all) { entry in
                Section {
                    row(for: entry)
                } header: {
                    Text(entry.displayName)
                } footer: {
                    if !entry.engineIntegrated {
                        Text("Engine wiring pending — downloading is supported, but playback won't route through this model yet.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                LabeledContent("Storage") {
                    Text(ModelStorage.modelsDirectory.path(percentEncoded: false))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func row(for entry: ModelEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.summary)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                statusLabel(for: entry)
                Spacer()
                action(for: entry)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusLabel(for entry: ModelEntry) -> some View {
        let status = manager.statuses[entry.id] ?? .notDownloaded
        switch status {
        case .notDownloaded:
            label("Not downloaded · \(entry.approximateSizeMB) MB", icon: "arrow.down.circle", color: .secondary)
        case .downloading(let completed, let total):
            label("Downloading file \(completed + 1) of \(total)…", icon: "arrow.down.circle", color: Color.readAloudTTSAccent)
        case .ready(let bytes):
            label("Installed · \(format(bytes: bytes))", icon: "checkmark.circle.fill", color: Color.readAloudTTSAccent)
        case .failed(let message):
            label(message, icon: "exclamationmark.circle", color: .red)
        }
    }

    private func label(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.system(size: 12)).foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func action(for entry: ModelEntry) -> some View {
        let status = manager.statuses[entry.id] ?? .notDownloaded
        switch status {
        case .notDownloaded:
            Button("Download") { Task { await manager.download(entry) } }
        case .downloading:
            ProgressView().controlSize(.small)
        case .ready:
            Button("Remove", role: .destructive) { manager.delete(entry) }
        case .failed:
            Button("Retry") { Task { await manager.download(entry) } }
        }
    }

    private func format(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
