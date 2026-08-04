import Foundation
import AppKit
import Observation

/// App-wide singleton that owns the menu-bar reader's playback
/// state. Separate from the per-window `SpeechPlayer` so menubar
/// actions don't fight a document the user is in the middle of
/// reading.
@Observable
@MainActor
final class MenuBarCommand {
    static let shared = MenuBarCommand()

    let player = SpeechPlayer()

    private let defaults = UserDefaults.standard
    private let hintShownKey = "app.humanreadtts.mac.shortcuts.didShowSelectionHint.v1"

    private init() {
        // When a menu-bar read finishes on its own, pull the next queued
        // item (if any and auto-advance is on). Document-window players
        // leave onReachedEnd nil, so the queue only chains menu-bar reads.
        player.onReachedEnd = { [weak self] in self?.handleReachedEnd() }
    }

    /// True while the menubar player is actively speaking — drives the
    /// animated menu-bar icon.
    var isSpeaking: Bool {
        if case .playing = player.state { return true }
        return false
    }

    /// Global-hotkey entry point: read the current selection from the
    /// frontmost app, falling back to the clipboard. Selection capture
    /// is best-effort (see `SelectionReader`); the clipboard path is
    /// always available in the sandbox. Shows a background HUD so the
    /// user gets feedback even with no app window open.
    func readSelectionOrClipboard() {
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        let originalClipboard = pasteboard.string(forType: .string)
        let snapshot = SelectionReader.snapshotItems(pasteboard)
        let restoreEnabled = SpeechSettings.shared.restoreClipboardAfterReading

        SelectionReader.synthesizeCopy()

        // Give the frontmost app a beat to service the synthetic ⌘C,
        // then read the result off the pasteboard. Async so we never
        // block the main thread on the copy round-trip.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [self] in
            let after = pasteboard.changeCount
            let copied = pasteboard.string(forType: .string)
            let outcome = SelectionReader.decide(
                beforeChangeCount: before,
                afterChangeCount: after,
                copiedString: copied,
                originalClipboard: originalClipboard,
                restoreEnabled: restoreEnabled
            )

            if outcome.source == .selection, outcome.shouldRestoreClipboard {
                SelectionReader.restore(snapshot, to: pasteboard)
            }

            guard let text = outcome.text else {
                ReadHUD.shared.show(
                    message: "Nothing to read — select some text or copy it first.",
                    systemImage: "text.badge.xmark",
                    showStop: false,
                    dismissAfter: 2.0
                )
                return
            }

            if outcome.selectionBlocked, outcome.source == .clipboard {
                maybeShowSelectionHint()
            }

            readText(text)
            ReadHUD.shared.show(
                message: hudPreview(text),
                showStop: true,
                dismissAfter: 3.0
            )
        }
    }

    /// Read the current clipboard. If it contains plain text,
    /// segment it into sentences, load into the menubar player,
    /// and start playback. Retained for the system Services path.
    func readClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        readText(text)
    }

    /// Segment arbitrary text into sentences, load into the
    /// menubar player, and start playback. Shared entry point for
    /// the clipboard reader and the system Services provider.
    func readText(_ text: String) {
        Task { @MainActor in
            let block = DocumentBlock(text: text, pageIndex: 0, offsetInPage: 0)
            let sentences = await SentenceSegmenter.segment([block], reflowLineWraps: true)
            player.load(sentences)
            player.togglePlayPause()
        }
    }

    /// Add text to the reading queue. If the reader is idle the item
    /// starts immediately; otherwise it waits behind the current read.
    /// Used by the menu-bar "Queue Clipboard" action and the queue UI.
    func enqueueText(_ text: String, title: String? = nil) {
        guard ReadingQueue.shared.enqueue(text, title: title) != nil else { return }
        if case .idle = player.state {
            advanceQueue()
        }
    }

    /// Pull and read the next queued item, if any.
    private func advanceQueue() {
        guard let item = ReadingQueue.shared.dequeueNext() else { return }
        readText(item.text)
    }

    /// `SpeechPlayer.onReachedEnd` hook — chain to the next queued item
    /// when auto-advance is on.
    private func handleReachedEnd() {
        guard ReadingQueue.shared.autoAdvance else { return }
        advanceQueue()
    }

    /// Convenience for the menubar button label.
    var playPauseLabel: String {
        switch player.state {
        case .idle: return "Resume"
        case .playing: return "Pause"
        case .paused: return "Resume"
        }
    }

    /// First few words of the text, collapsed to one line, for the HUD.
    private func hudPreview(_ text: String) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.count <= 48 ? collapsed : String(collapsed.prefix(48)) + "…"
    }

    /// One-time, dismissible nudge shown the first time we fell back to
    /// the clipboard because the synthetic copy didn't register —
    /// likely because Accessibility access isn't granted. Never nags
    /// again after the first showing.
    private func maybeShowSelectionHint() {
        guard !defaults.bool(forKey: hintShownKey) else { return }
        defaults.set(true, forKey: hintShownKey)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "HumanReadTTS read your clipboard"
        alert.informativeText = "To read the selected text directly from other apps, grant HumanReadTTS Accessibility access in System Settings. Until then, copy text (⌘C) and press the shortcut to hear it."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            SelectionPermission.openAccessibilitySettings()
        }
    }
}
