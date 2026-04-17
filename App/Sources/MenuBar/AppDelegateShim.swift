import AppKit
import SwiftUI
import Carbon.HIToolbox

/// Bridges into `NSApplication` lifecycle to register bits that
/// SwiftUI's `App` protocol doesn't expose: the Services provider
/// (for the system "Read with Rhea" menu item) and a global
/// ⌘⇧S hotkey (reads the clipboard from anywhere).
///
/// Wired via `@NSApplicationDelegateAdaptor` in `RheaApp`.
final class AppDelegateShim: NSObject, NSApplicationDelegate {
    private var servicesProvider: ServicesProvider?
    private var globalHotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let provider = ServicesProvider()
        NSApp.servicesProvider = provider
        servicesProvider = provider
        NSUpdateDynamicServices()

        globalHotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: UInt32(cmdKey | shiftKey)
        ) {
            Task { @MainActor in MenuBarCommand.shared.readClipboard() }
        }
    }
}
