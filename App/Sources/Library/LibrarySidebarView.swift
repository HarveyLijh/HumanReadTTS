import SwiftUI

/// Sidebar list of recently-opened documents. Click to reopen; the
/// owning `RootView` handles the bookmark resolution and swap.
///
/// Right-click surfaces two per-entry actions:
///   * "Generate Audio…" — opens the dedicated export options sheet
///     for the right-clicked entry (independent of whatever the user
///     currently has open).
///   * "Remove from Library" — drops the entry + saved reading
///     position. The underlying file is untouched.
struct LibrarySidebarView: View {
    @Bindable var library: Library
    @Bindable var exporter = ExportCoordinator.shared
    @Binding var selectedID: LibraryEntry.ID?
    /// Called when the user picks "Generate Audio…" from an entry's
    /// context menu. The parent view resolves the entry into a sheet
    /// presentation; keeping this as a closure means the sidebar
    /// doesn't need to know about the sheet's state.
    var onRequestExport: (LibraryEntry) -> Void = { _ in }
    /// Called when the user picks "Remove from Library". The parent
    /// forwards to `library.remove(id:)` so it can also clean up
    /// selection and other related UI state.
    var onRequestRemove: (LibraryEntry) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            List(selection: $selectedID) {
                if library.entries.isEmpty {
                    emptyRow
                } else {
                    ForEach(library.entries) { entry in
                        row(for: entry)
                            .tag(entry.id)
                            .contextMenu {
                                Button {
                                    onRequestExport(entry)
                                } label: {
                                    Label(
                                        "Generate Audio for Entire Article…",
                                        systemImage: "waveform.badge.plus"
                                    )
                                }
                                Divider()
                                Button(role: .destructive) {
                                    onRequestRemove(entry)
                                } label: {
                                    Label(
                                        "Remove from Library",
                                        systemImage: "xmark.bin"
                                    )
                                }
                            }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .navigationTitle("Library")
    }

    /// Top-of-sidebar row with quick-create buttons. "New note" posts
    /// the same notification as ⌘N so the create-scratchpad flow is
    /// discoverable for users who don't remember the shortcut.
    /// "Open file…" is the obvious companion.
    private var toolbar: some View {
        HStack(spacing: 6) {
            Button {
                NotificationCenter.default.post(
                    name: AppScene.newScratchpadNotification, object: nil
                )
            } label: {
                Label("New note", systemImage: "square.and.pencil")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.rheaAccent)
            .controlSize(.small)
            .help("Create a blank scratchpad · ⌘N")

            Button {
                NotificationCenter.default.post(
                    name: AppScene.openFileNotification, object: nil
                )
            } label: {
                Label("Open…", systemImage: "folder")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Open a PDF, Markdown, or EPUB · ⌘O")

            queueButton

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// Always-visible export queue indicator. Reflects
    /// ExportCoordinator state at a glance: tray when empty, waveform
    /// + "running·queued" while jobs are in flight, orange triangle
    /// when the most recent run failed. Click opens the dedicated
    /// Exports window so the user never has to remember ⌘⇧J.
    private var queueButton: some View {
        Button {
            NotificationCenter.default.post(
                name: AppScene.showExportsNotification, object: nil
            )
        } label: {
            HStack(spacing: 3) {
                Image(systemName: queueIconName)
                if let label = queueCountLabel {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(queueTint)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(queueTooltip)
    }

    private var queueRunning: Int {
        exporter.jobs.filter {
            if case .running = $0.state { return true }
            return false
        }.count
    }

    private var queueQueued: Int {
        exporter.jobs.filter {
            if case .queued = $0.state { return true }
            return false
        }.count
    }

    private var queueFailedRecent: Bool {
        if case .failed = exporter.state { return true }
        return false
    }

    private var queueIconName: String {
        if queueRunning > 0 { return "waveform" }
        if queueQueued > 0 { return "hourglass" }
        if queueFailedRecent { return "exclamationmark.triangle.fill" }
        return "tray"
    }

    private var queueCountLabel: String? {
        if queueRunning > 0 && queueQueued > 0 {
            return "\(queueRunning)·\(queueQueued)"
        }
        if queueRunning > 0 { return "\(queueRunning)" }
        if queueQueued > 0 { return "\(queueQueued)" }
        return nil
    }

    private var queueTint: Color {
        if queueRunning > 0 || queueQueued > 0 { return Color.rheaAccent }
        if queueFailedRecent { return .orange }
        return .secondary
    }

    private var queueTooltip: String {
        if queueRunning > 0 || queueQueued > 0 {
            return "Exports: \(queueRunning) running, \(queueQueued) queued — click to open (⌘⇧J)"
        }
        if queueFailedRecent { return "Last export failed — click to open the queue (⌘⇧J)" }
        return "Open the export queue (⌘⇧J)"
    }

    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No documents yet")
                .font(RheaFont.ui(13))
                .foregroundStyle(.secondary)
            Text("Drop a PDF, Markdown, or EPUB file anywhere in the window.")
                .font(RheaFont.ui(11))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func row(for entry: LibraryEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.title)
                .font(RheaFont.ui(13))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(Self.formatted(entry.lastOpened))
                .font(RheaFont.ui(11))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// Finder-style stable timestamp. `Text(_, style: .relative)`
    /// re-renders every second ("2 min, 32 sec ago" ticking up),
    /// which is visually noisy for a library that's open for hours.
    /// We swap to a snapshot at render time: "Today 3:42 PM",
    /// "Yesterday", or "Apr 11" for anything older.
    static func formatted(_ date: Date, relativeTo now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today \(timeFormatter.string(from: date))"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        if let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
           date >= startOfWeek {
            return weekdayFormatter.string(from: date)
        }
        return monthDayFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f
    }()
}
