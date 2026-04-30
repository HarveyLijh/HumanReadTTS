import Foundation
import Observation

/// App-wide buffer for in-progress markdown edits. The reader hands
/// every opened file off to the store on load, the editor updates
/// `currentText` on each keystroke, and the rest of the UI (sidebar
/// dot, window-edited indicator, quit warning) reads `isDirty(...)`
/// to decide what to display or block.
///
/// The store survives switching between library entries — when the
/// user reopens a file with unsaved edits, the dirty buffer is
/// preserved instead of being clobbered by the on-disk contents.
@Observable
@MainActor
final class MarkdownDocumentStore {
    static let shared = MarkdownDocumentStore()

    /// Per-file edit state, keyed by `URL.standardizedFileURL.path`
    /// so two URLs that point at the same file (e.g. through symlinks
    /// vs. real paths) collapse to one entry.
    private(set) var documents: [String: Document] = [:]

    struct Document: Equatable {
        let url: URL
        /// Last text successfully written to disk (or read on load).
        var savedText: String
        /// Live editor buffer — what the user sees in Source mode.
        var currentText: String
        var isDirty: Bool { currentText != savedText }
    }

    /// Called by the reader when a markdown file finishes loading.
    /// Preserves any in-flight dirty buffer so reopening the same file
    /// (after switching to a PDF and back) doesn't blow away unsaved
    /// edits.
    func register(url: URL, contents: String) {
        let key = url.standardizedFileURL.path
        if let existing = documents[key], existing.isDirty {
            // Refresh the saved baseline in case the file changed on
            // disk while we had a dirty buffer; the user will see the
            // updated baseline if they discard.
            documents[key] = Document(
                url: existing.url,
                savedText: contents,
                currentText: existing.currentText
            )
            return
        }
        documents[key] = Document(
            url: url,
            savedText: contents,
            currentText: contents
        )
    }

    /// Called by the editor whenever the text view's storage changes.
    /// If we don't have a registered baseline yet, treat the first
    /// snapshot as both saved and current so isDirty stays false until
    /// the user actually types.
    func update(url: URL, text: String) {
        let key = url.standardizedFileURL.path
        if var doc = documents[key] {
            guard doc.currentText != text else { return }
            doc.currentText = text
            documents[key] = doc
        } else {
            documents[key] = Document(
                url: url,
                savedText: text,
                currentText: text
            )
        }
    }

    /// Persist the current buffer to disk. Returns `true` on success;
    /// the caller is responsible for surfacing failure to the user.
    @discardableResult
    func save(url: URL) -> Bool {
        let key = url.standardizedFileURL.path
        guard var doc = documents[key] else { return false }
        do {
            try doc.currentText.write(to: url, atomically: true, encoding: .utf8)
            doc.savedText = doc.currentText
            documents[key] = doc
            return true
        } catch {
            return false
        }
    }

    /// Throw away unsaved edits, restoring the on-disk baseline as the
    /// editor's current text. Used by the "Don't Save" branch of the
    /// close / quit confirmation sheet.
    func discard(url: URL) {
        let key = url.standardizedFileURL.path
        guard var doc = documents[key] else { return }
        doc.currentText = doc.savedText
        documents[key] = doc
    }

    func isDirty(url: URL) -> Bool {
        documents[url.standardizedFileURL.path]?.isDirty ?? false
    }

    func isDirty(path: String) -> Bool {
        documents[path]?.isDirty ?? false
    }

    /// Latest editor buffer for `url`, or `nil` if the file has never
    /// been opened in this session.
    func currentText(url: URL) -> String? {
        documents[url.standardizedFileURL.path]?.currentText
    }

    /// All files with unsaved edits, in insertion order. Used by the
    /// quit-confirmation flow to enumerate what's at risk.
    var dirtyDocuments: [Document] {
        documents.values.filter(\.isDirty)
    }

    /// True if any opened file has unsaved edits — drives the
    /// applicationShouldTerminate check.
    var hasAnyDirty: Bool {
        documents.values.contains(where: \.isDirty)
    }
}
