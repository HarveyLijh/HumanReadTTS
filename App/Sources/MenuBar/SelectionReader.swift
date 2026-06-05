import AppKit
import Carbon.HIToolbox
import CoreGraphics
import KeyboardShortcuts

/// The single system-wide shortcut for "read aloud from anywhere".
///
/// `KeyboardShortcuts` wraps the same Carbon `RegisterEventHotKey`
/// path that this app used to hand-roll (sandbox / Mac App Store
/// safe, no Accessibility permission for the hotkey *itself*), and
/// adds a SwiftUI recorder, `UserDefaults` persistence, and conflict
/// detection. The default is ⌘⇧E — deliberately chosen to dodge
/// ⌘⇧S ("Save As") and ⌘⇧R ("Reload"), both of which the old
/// hard-coded binding collided with.
extension KeyboardShortcuts.Name {
    static let readSelection = Self(
        "readSelection",
        default: .init(.e, modifiers: [.command, .shift])
    )
}

/// Decides *what to read* when the global hotkey fires, and owns the
/// sandbox-aware mechanics of grabbing the frontmost app's selection.
///
/// Strategy: synthesize ⌘C so the frontmost app copies its current
/// selection to the pasteboard, read it, then restore the user's
/// previous clipboard. If the synthetic copy never registers (nothing
/// selected, a secure field, or the OS blocked the event), fall back
/// to reading the existing clipboard. Reading the clipboard is always
/// permitted in the sandbox; the selection path is best-effort.
///
/// The branch logic lives in `decide(...)` as a pure function so it
/// can be unit-tested without a live pasteboard.
enum SelectionReader {

    enum Source: Equatable { case selection, clipboard }

    struct Outcome: Equatable {
        /// Trimmed text to read, or `nil` when there's nothing.
        var text: String?
        /// Where the text came from (`nil` when `text` is `nil`).
        var source: Source?
        /// Whether the caller should restore the saved clipboard —
        /// only meaningful when `source == .selection`.
        var shouldRestoreClipboard: Bool
        /// True when we fell back to the clipboard because the
        /// synthetic copy never advanced the pasteboard — a hint that
        /// live selection reading may be permission-blocked (vs. the
        /// user simply having nothing selected).
        var selectionBlocked: Bool
    }

    /// Pure decision. Given the pasteboard change-counts before and
    /// after a synthetic ⌘C, the string present after the copy, and
    /// the original clipboard string, decide what to read.
    static func decide(
        beforeChangeCount: Int,
        afterChangeCount: Int,
        copiedString: String?,
        originalClipboard: String?,
        restoreEnabled: Bool
    ) -> Outcome {
        let advanced = afterChangeCount != beforeChangeCount

        if advanced, let selection = trimmedNonEmpty(copiedString) {
            return Outcome(
                text: selection,
                source: .selection,
                shouldRestoreClipboard: restoreEnabled,
                selectionBlocked: false
            )
        }

        // Fall back to whatever was already on the clipboard.
        if let clip = trimmedNonEmpty(originalClipboard) {
            return Outcome(
                text: clip,
                source: .clipboard,
                shouldRestoreClipboard: false,
                selectionBlocked: !advanced
            )
        }

        return Outcome(
            text: nil,
            source: nil,
            shouldRestoreClipboard: false,
            selectionBlocked: !advanced
        )
    }

    private static func trimmedNonEmpty(_ string: String?) -> String? {
        guard let string else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Live capture (impure; main actor)

    /// Snapshot the general pasteboard faithfully enough to put it
    /// back after a synthetic copy. Copies every type's data for each
    /// item into a detached `NSPasteboardItem`.
    @MainActor
    static func snapshotItems(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        pasteboard.pasteboardItems?.compactMap { item in
            let copy = NSPasteboardItem()
            var wroteAnything = false
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                    wroteAnything = true
                }
            }
            return wroteAnything ? copy : nil
        } ?? []
    }

    @MainActor
    static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        guard !items.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }

    /// Post a synthetic ⌘C to the session so the frontmost app copies
    /// its current selection to the pasteboard. No-op if the OS blocks
    /// the event (handled downstream by the change-count check).
    static func synthesizeCopy() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true
        )
        down?.flags = .maskCommand
        let up = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false
        )
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}

/// Helpers for the (optional) Accessibility permission that unlocks
/// reading another app's live selection. The sandboxed build always
/// works via the clipboard; this is the upgrade path.
enum SelectionPermission {
    static func openAccessibilitySettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
