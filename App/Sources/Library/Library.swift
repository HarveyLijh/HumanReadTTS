import Foundation
import Observation

/// Recent-files library. In-memory plus UserDefaults persistence
/// via JSON-encoded `[LibraryEntry]`. Cloud sync (CloudKit) is
/// explicitly deferred to Phase 3 per MILESTONES §2.
///
/// Bookmarks are created with `.withSecurityScope` so the same
/// Library implementation works in both the sandbox-off Debug
/// build and the sandbox-on Release build; non-sandboxed resolution
/// simply ignores the security scope.
@Observable
@MainActor
final class Library {
    private(set) var entries: [LibraryEntry] = []

    private let defaults: UserDefaults
    private let key = "app.rhea.mac.library.entries.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Record that the user opened `url`. Moves an existing entry
    /// for the same resolved file to the top and updates its
    /// timestamp; creates a new entry otherwise.
    func record(url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            entries.removeAll { existing in
                guard let resolved = resolve(existing) else { return false }
                defer { existing.stopAccess(resolved: resolved) }
                return resolved.resolvedURLs(with: url)
            }
            let entry = LibraryEntry(
                title: url.lastPathComponent,
                lastOpened: Date(),
                bookmarkData: bookmark
            )
            entries.insert(entry, at: 0)
            save()
        } catch {
            // Best-effort only; a failed bookmark isn't fatal. The
            // file just won't appear in the recents list.
        }
    }

    /// Resolve a bookmark back to a URL. The returned URL has had
    /// `startAccessingSecurityScopedResource()` called on it; the
    /// caller is responsible for the matching `stop` when done.
    func resolve(_ entry: LibraryEntry) -> URL? {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: entry.bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            _ = url.startAccessingSecurityScopedResource()
            return url
        } catch {
            return nil
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: key) else { return }
        do {
            entries = try JSONDecoder().decode([LibraryEntry].self, from: data)
        } catch {
            entries = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            defaults.set(data, forKey: key)
        } catch {
            // Persistence is best-effort.
        }
    }
}

private extension LibraryEntry {
    /// Balances a `resolve` call without exposing the URL.
    func stopAccess(resolved: URL) {
        resolved.stopAccessingSecurityScopedResource()
    }
}

private extension URL {
    /// Loose equality: both URLs resolve to the same filesystem
    /// path after removing percent-encoding. Avoids false negatives
    /// from trailing slashes and `file://` prefix variations.
    func resolvedURLs(with other: URL) -> Bool {
        self.standardizedFileURL.path == other.standardizedFileURL.path
    }
}
