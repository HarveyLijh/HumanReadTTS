import SwiftUI

/// Sidebar list of recently-opened documents. Click to reopen; the
/// owning `RootView` handles the bookmark resolution and swap.
struct LibrarySidebarView: View {
    @Bindable var library: Library
    @Binding var selectedID: LibraryEntry.ID?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            List(selection: $selectedID) {
                if library.entries.isEmpty {
                    emptyRow
                } else {
                    ForEach(library.entries) { entry in
                        row(for: entry).tag(entry.id)
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

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
