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

    /// LaunchServices routes `open -a Rhea file.pdf` and Finder
    /// double-clicks here. Without this override, SwiftUI's
    /// `WindowGroup` spawns a new window per URL event — wrong for
    /// a reader that keeps one document visible at a time. We
    /// front the existing main window and repost each URL as a
    /// notification that `RootView` observes via its existing
    /// drop/adopt code path, swapping the document in place.
    func application(_ application: NSApplication, open urls: [URL]) {
        Self.closeExtraMainWindows()
        if let window = NSApp.windows.first(where: { Self.isMainWindow($0) }) {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        for url in urls {
            NotificationCenter.default.post(
                name: .rheaOpenURL, object: nil, userInfo: ["url": url]
            )
        }
    }

    /// A `WindowGroup` scoped with `handlesExternalEvents(matching:)`
    /// should ignore URL events, but in case SwiftUI or another
    /// code path still spawns a duplicate of the reader window, we
    /// close all but the first. Cheap to call on every URL open.
    private static func closeExtraMainWindows() {
        let mains = NSApp.windows.filter(isMainWindow)
        guard mains.count > 1 else { return }
        for window in mains.dropFirst() {
            window.close()
        }
    }

    private static func isMainWindow(_ window: NSWindow) -> Bool {
        // The reader window carries the WindowGroup title. Settings
        // and auxiliary panels use other titles or aren't NSWindow
        // subclasses we care about here.
        window.title == "Rhea"
    }

    /// Prevent the "dock-click-to-open-new-untitled-window" behavior
    /// — we always keep the one reader window around.
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag, let window = NSApp.windows.first(where: { $0.title == "Rhea" }) {
            window.makeKeyAndOrderFront(nil)
            return false
        }
        return true
    }
}

extension Notification.Name {
    /// Posted by `AppDelegateShim.application(_:open:)` so the main
    /// SwiftUI scene can adopt the URL without spawning a new window.
    static let rheaOpenURL = Notification.Name("app.rhea.mac.openURL")
}
