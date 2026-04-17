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

    private init() {}

    /// Read the current clipboard. If it contains plain text,
    /// segment it into sentences, load into the menubar player,
    /// and start playback.
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
            let sentences = await SentenceSegmenter.segment([block])
            player.load(sentences)
            player.togglePlayPause()
        }
    }

    /// Convenience for the menubar button label.
    var playPauseLabel: String {
        switch player.state {
        case .idle: return "Resume"
        case .playing: return "Pause"
        case .paused: return "Resume"
        }
    }
}
