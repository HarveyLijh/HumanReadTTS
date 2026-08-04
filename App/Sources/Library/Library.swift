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
    private let key = "app.humanreadtts.mac.library.entries.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Record that the user opened `url`. Moves an existing entry
    /// for the same file path to the top and updates its
    /// timestamp; creates a new entry otherwise. Preserves any
    /// previously-stored `lastSentenceIndex` so reopening the same
    /// document restores reading position.
    ///
    /// Dedup compares stored `originalPath` strings — never resolves
    /// existing bookmarks — so recording a drop doesn't trigger TCC
    /// consent prompts for every other library entry that happens
    /// to live in Documents / Downloads / Desktop.
    func record(url: URL) {
        do {
            let canonicalPath = url.standardizedFileURL.path
            let bookmark = try url.bookmarkData(
                options: Self.bookmarkCreationOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let previousPosition = entries
                .first(where: { $0.originalPath == canonicalPath })?
                .lastSentenceIndex
            entries.removeAll { existing in
                existing.originalPath == canonicalPath
            }
            let entry = LibraryEntry(
                title: url.lastPathComponent,
                lastOpened: Date(),
                bookmarkData: bookmark,
                originalPath: canonicalPath,
                lastSentenceIndex: previousPosition
            )
            entries.insert(entry, at: 0)
            save()
        } catch {
            // Best-effort only; a failed bookmark isn't fatal. The
            // file just won't appear in the recents list.
        }
    }

    /// Persist the current reading position for `url`. Called from
    /// the RootView's playback-state observer so every sentence
    /// advance snapshots where the user is — a crash or abrupt quit
    /// loses at most one sentence. No-op when `url` isn't tracked
    /// (shouldn't happen, since `record(url:)` runs before playback
    /// starts).
    func recordPosition(url: URL, sentenceIndex: Int) {
        let canonicalPath = url.standardizedFileURL.path
        guard let idx = entries.firstIndex(where: {
            $0.originalPath == canonicalPath
        }) else { return }
        guard entries[idx].lastSentenceIndex != sentenceIndex else {
            return
        }
        entries[idx].lastSentenceIndex = sentenceIndex
        save()
    }

    /// Drop the recents entry (and its bookmark + saved position).
    /// The underlying file is untouched — "remove from library" is
    /// strictly a UI-surface operation, same as Finder's "Remove
    /// from Recents". No-op when the id isn't in the list.
    func remove(id: LibraryEntry.ID) {
        let before = entries.count
        entries.removeAll { $0.id == id }
        guard entries.count != before else { return }
        save()
    }

    /// Resume index stored alongside `url`, if any. Used by the
    /// reader on document load to seek the player to a paused state
    /// at the last-known sentence.
    func savedPosition(for url: URL) -> Int? {
        let canonicalPath = url.standardizedFileURL.path
        return entries
            .first(where: { $0.originalPath == canonicalPath })?
            .lastSentenceIndex
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
