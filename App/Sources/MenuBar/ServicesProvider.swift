import AppKit

/// Exposes ReadAloudTTS to the system Services menu. When the user picks
/// "Read with ReadAloudTTS" from any app's Services submenu, macOS delivers
/// the current selection on a pasteboard and calls `readSelection`,
/// which hands the text off to the menubar player.
///
/// The provider must be an `NSObject` subclass with an `@objc`
/// selector whose signature matches the one declared in
/// `Info.plist → NSServices → NSMessage` (here, `readSelection`).
@MainActor
final class ServicesProvider: NSObject {
    @objc func readSelection(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let text = pboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "ReadAloudTTS couldn't read the selection." as NSString
            return
        }
        MenuBarCommand.shared.readText(text)
    }
}
