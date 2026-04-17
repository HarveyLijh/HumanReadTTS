import AppKit
import Carbon.HIToolbox

/// Registers a single system-wide keyboard shortcut via the Carbon
/// HotKey API. Unlike `NSEvent.addGlobalMonitorForEvents`, this
/// *intercepts* the keystroke (it doesn't also reach the focused
/// app) and doesn't require Accessibility permission. The Carbon
/// Events API is deprecated-but-shipping on macOS 26 and remains
/// the standard way to do this from a sandboxed app.
///
/// One instance = one hotkey. Rhea binds ⌘⇧S to "read clipboard"
/// so the user can start listening without switching apps.
final class GlobalHotKey {
    // Carbon pointer refs — single-owner, released on deinit.
    // `nonisolated(unsafe)` because deinit runs without an actor.
    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var eventHandler: EventHandlerRef?

    /// Shared retention so the C event-handler callback can find a
    /// live Swift closure without capturing self across the Carbon
    /// bridge. Keyed by `EventHotKeyID.id`.
    nonisolated(unsafe) private static var handlers: [UInt32: @Sendable () -> Void] = [:]
    nonisolated(unsafe) private static var nextID: UInt32 = 1

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping @Sendable () -> Void) {
        let id = Self.nextID
        Self.nextID += 1
        Self.handlers[id] = handler

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x52_48_4B_59),  // 'RHKY'
            id: id
        )
        RegisterEventHotKey(
            keyCode, modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var firedID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &firedID
                )
                if let cb = GlobalHotKey.handlers[firedID.id] {
                    DispatchQueue.main.async(execute: cb)
                }
                return noErr
            },
            1, &eventSpec, nil, &eventHandler
        )
    }

    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }
}
