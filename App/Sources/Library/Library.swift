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
                options: Self.bookmarkCreationOptions,
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

    /// Resolve a bookmark back to a URL. Tries both plain and
    /// security-scoped resolution so a user whose library was
    /// recorded by an older build (which always used
    /// `.withSecurityScope`) still works after the fix.
    func resolve(_ entry: LibraryEntry) -> URL? {
        let modes: [URL.BookmarkResolutionOptions] = Self.isSandboxed
            ? [[.withSecurityScope], []]
            : [[], [.withSecurityScope]]

        for mode in modes {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: entry.bookmarkData,
                options: mode,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if mode.contains(.withSecurityScope) {
                    _ = url.startAccessingSecurityScopedResource()
                }
                return url
            }
        }
        return nil
    }

    /// Non-sandboxed Developer-ID builds don't need (and actively
    /// can't use) security-scoped bookmarks — plain bookmarks are
    /// what survive restarts. Detect at runtime so the same code
    /// does the right thing in both Debug (sandbox off) and Release
    /// (sandbox on, per ADR-003).
    private static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    private static var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        isSandboxed ? [.withSecurityScope] : []
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
