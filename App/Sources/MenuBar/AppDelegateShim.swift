import AppKit
import SwiftUI
import KeyboardShortcuts

/// Bridges into `NSApplication` lifecycle to register bits that
/// SwiftUI's `App` protocol doesn't expose: the Services provider
/// (for the system "Read with ReadAloudTTS" menu item) and the global
/// "read selection from anywhere" hotkey (default ⌘⇧E, rebindable in
/// Settings → Shortcuts).
///
/// Wired via `@NSApplicationDelegateAdaptor` in `ReadAloudTTSApp`.
final class AppDelegateShim: NSObject, NSApplicationDelegate {
    private var servicesProvider: ServicesProvider?
    private var fontShortcutMonitor: Any?
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register the bundled SIL-OFL reading faces (OpenDyslexic,
        // Atkinson Hyperlegible) so `NSFont(name:)` resolves them for the
        // Reading settings font picker. Idempotent and cheap.
        ReaderFonts.registerBundledFonts()

        let provider = ServicesProvider()
        NSApp.servicesProvider = provider
        servicesProvider = provider
        NSUpdateDynamicServices()

        // System-wide read trigger. `KeyboardShortcuts` keeps the
        // binding in UserDefaults and seeds the ⌘⇧E default, so the
        // hotkey is live from first launch and rebindable in Settings.
        KeyboardShortcuts.onKeyUp(for: .readSelection) {
            Task { @MainActor in MenuBarCommand.shared.readSelectionOrClipboard() }
        }

        // Read a screenshot: OCR an image sitting on the clipboard (e.g.
        // from ⌃⇧⌘4) and speak it. Default ⌘⇧2, rebindable in Settings.
        KeyboardShortcuts.onKeyUp(for: .readScreenshot) {
            Task { @MainActor in MenuBarCommand.shared.readClipboardImage() }
        }

        // Publish reads to Control Center / lock screen / media keys and
        // wire the hardware transport (play/pause/next/prev/stop).
        NowPlayingController.shared.activate()

        installFontShortcutMonitor()
        installMemoryPressureHandler()
    }

    /// Under system memory pressure, hand MLX's reclaimable buffer
    /// cache back to the OS. This frees only unused cached buffers (not
    /// live model weights), so it's safe mid-playback — we stop hoarding
    /// without interrupting reading. The cache otherwise sits at the
    /// session's high-water mark until playback stops.
    private func installMemoryPressureHandler() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler {
            Task { @MainActor in KokoroEngine.shared.releaseCache() }
        }
        source.resume()
        memoryPressureSource = source
    }

    /// Local keyDown monitor that fires zoom / font-size notifications
    /// for every common ⌘+/⌘-/⌘0 variant. SwiftUI's
    /// `.keyboardShortcut("+", modifiers: [.command])` is finicky on
    /// US keyboards where "+" needs shift — the matcher demands exact
    /// modifier flags, so `⌘⇧+` fails to fire a shortcut bound to
    /// `[.command]` only. Catching at the NSEvent layer avoids the
    /// guesswork and reliably handles ⌘= (no shift), ⌘+ (shift),
    /// ⌘-, and ⌘0 from any window.
    private func installFontShortcutMonitor() {
        if let token = fontShortcutMonitor {
            NSEvent.removeMonitor(token)
        }
        fontShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            event in
            // Filter to events that look like font-zoom shortcuts.
            // Ignore presses while the user is typing in a text-input
            // field that isn't part of a reader (e.g. the Settings
            // form fields), so the shortcut doesn't preempt
            // normal text editing.
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods.contains(.command) else { return event }
            // The character WITH modifiers — so ⌘⇧= gives us "+",
            // ⌘= gives us "=". Combined with `charactersIgnoringModifiers`
            // we cover both shifted and unshifted variants reliably.
            let withMods = event.characters ?? ""
            let raw = event.charactersIgnoringModifiers ?? ""

            let isPlus = withMods.contains("+") || raw == "=" || raw == "+"
            let isMinus = withMods.contains("-") || raw == "-" || raw == "_"
            let isZero = withMods == "0" || raw == "0"
            let isFit = withMods == "9" || raw == "9"

            // Don't steal events from any non-reader text editor. The
            // markdown reader and scratchpad use NSTextView, but
            // their shortcut handling tolerates this monitor running
            // first — the notification simply re-rescales the storage.
            // Settings sheets use SwiftUI TextField; those don't get
            // intercepted because the keystrokes that matter there
            // (⌘+/-/0) aren't normal text editing operations.
            if isPlus {
                NotificationCenter.default.post(
                    name: AppScene.increaseFontNotification, object: nil
                )
                return nil
            }
            if isMinus {
                NotificationCenter.default.post(
                    name: AppScene.decreaseFontNotification, object: nil
                )
                return nil
            }
            if isZero {
                NotificationCenter.default.post(
                    name: AppScene.resetFontNotification, object: nil
                )
                return nil
            }
            if isFit {
                NotificationCenter.default.post(
                    name: AppScene.zoomToFitNotification, object: nil
                )
                return nil
            }
            return event
        }
    }

    deinit {
        if let token = fontShortcutMonitor {
            NSEvent.removeMonitor(token)
        }
    }

    /// LaunchServices routes `open -a ReadAloudTTS file.pdf` and Finder
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
                name: .readAloudTTSOpenURL, object: nil, userInfo: ["url": url]
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
        window.title == "ReadAloudTTS"
    }

    /// Prevent the "dock-click-to-open-new-untitled-window" behavior
    /// — we always keep the one reader window around.
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag, let window = NSApp.windows.first(where: { $0.title == "ReadAloudTTS" }) {
            window.makeKeyAndOrderFront(nil)
            return false
        }
        return true
    }

    /// Block quit while any markdown buffer is dirty; walk the user
    /// through Save / Don't Save / Cancel for each. The dialog is
    /// modeled on macOS HIG: per-file prompts when up to a couple of
    /// docs are dirty (small N keeps cognitive load low). On Cancel
    /// from any prompt, we abort the whole quit and return control to
    /// the user.
    @MainActor
    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        if MarkdownSavePrompt.confirmAllDirty() {
            return .terminateNow
        }
        return .terminateCancel
    }
}

/// Forwarding NSWindowDelegate that gates close attempts on dirty
/// markdown buffers without dispossessing the original delegate. SwiftUI
/// installs its own internal delegate to drive scene state, so we sit
/// in between: every method we don't care about gets re-dispatched to
/// the captured upstream delegate, and only `windowShouldClose` adds
/// the Save / Don't Save / Cancel prompt.
@MainActor
final class DirtyCloseGuard: NSObject, NSWindowDelegate {
    /// Strong references keyed by the window so the guard outlives the
    /// transient `WindowAccessor` callback that installs it.
    private static var guards: [ObjectIdentifier: DirtyCloseGuard] = [:]

    private weak var window: NSWindow?
    private weak var upstream: (any NSWindowDelegate)?

    static func attach(to window: NSWindow) {
        let id = ObjectIdentifier(window)
        guard guards[id] == nil else { return }
        let guardObj = DirtyCloseGuard()
        guardObj.window = window
        guardObj.upstream = window.delegate
        window.delegate = guardObj
        guards[id] = guardObj
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Auxiliary panels (Settings, Exports, Onboarding) don't own a
        // markdown buffer; let them close immediately.
        guard sender.title == "ReadAloudTTS" || sender.title.isEmpty else {
            return upstream?.windowShouldClose?(sender) ?? true
        }
        guard MarkdownSavePrompt.confirmAllDirty() else { return false }
        return upstream?.windowShouldClose?(sender) ?? true
    }

    /// Forward unknown selectors to the SwiftUI delegate so its
    /// internal scene tracking keeps working.
    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return upstream?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let upstream, upstream.responds(to: aSelector) {
            return upstream
        }
        return nil
    }
}

/// Shared entry point for the Save / Don't Save / Cancel sheet flow.
/// Lives at the app delegate layer so quit and window-close use the
/// exact same prompts in the exact same order.
enum MarkdownSavePrompt {
    /// Walks every dirty markdown document. Returns `true` when it's
    /// safe to proceed (every dirty file got either saved or
    /// explicitly discarded), `false` when the user cancelled at any
    /// point.
    @MainActor
    static func confirmAllDirty() -> Bool {
        let store = MarkdownDocumentStore.shared
        let dirty = store.dirtyDocuments
        guard !dirty.isEmpty else { return true }

        for doc in dirty {
            switch promptForSingle(doc, totalDirty: dirty.count) {
            case .save:
                if !store.save(url: doc.url) {
                    let alert = NSAlert()
                    alert.messageText = "Couldn't save \(doc.url.lastPathComponent)."
                    alert.informativeText = "The file may be read-only or moved."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Cancel")
                    alert.runModal()
                    return false
                }
            case .discard:
                store.discard(url: doc.url)
            case .cancel:
                return false
            }
        }
        return true
    }

    private enum Outcome {
        case save
        case discard
        case cancel
    }

    @MainActor
    private static func promptForSingle(
        _ doc: MarkdownDocumentStore.Document,
        totalDirty: Int
    ) -> Outcome {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Do you want to save changes to \(doc.url.lastPathComponent)?"
        alert.informativeText = totalDirty > 1
            ? "Your changes will be lost if you don't save them. (\(totalDirty) files have unsaved changes.)"
            : "Your changes will be lost if you don't save them."
        // Order matches the system Save panel: default Save, secondary
        // Cancel, destructive Don't Save on the far end.
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")

        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .cancel
        case .alertThirdButtonReturn: return .discard
        default: return .cancel
        }
    }
}

extension Notification.Name {
    /// Posted by `AppDelegateShim.application(_:open:)` so the main
    /// SwiftUI scene can adopt the URL without spawning a new window.
    static let readAloudTTSOpenURL = Notification.Name("app.readaloudtts.mac.openURL")

    /// Posted by the Settings "Show Welcome Tour" button and the
    /// Help menu entry so the RootView (which owns an
    /// `openWindow` environment handle) can raise the onboarding
    /// window without direct SwiftUI plumbing.
    static let readAloudTTSShowOnboarding = Notification.Name("app.readaloudtts.mac.showOnboarding")
}
