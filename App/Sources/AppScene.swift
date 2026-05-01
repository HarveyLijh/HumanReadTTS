import SwiftUI
import AppKit

struct AppScene: Scene {
    /// Menu commands need a reference to the current RootView to
    /// invoke its flows. NotificationCenter keeps command→view
    /// plumbing decoupled so the command can originate from any
    /// window without threading bindings through the hierarchy.
    static let exportNotification = Notification.Name("app.rhea.mac.export")
    static let showExportsNotification = Notification.Name("app.rhea.mac.showExports")
    static let playPauseNotification = Notification.Name("app.rhea.mac.playPause")
    static let nextSentenceNotification = Notification.Name("app.rhea.mac.nextSentence")
    static let prevSentenceNotification = Notification.Name("app.rhea.mac.prevSentence")
    static let openFileNotification = Notification.Name("app.rhea.mac.openFile")
    static let newScratchpadNotification = Notification.Name("app.rhea.mac.newScratchpad")
    static let speedFasterNotification = Notification.Name("app.rhea.mac.speedFaster")
    static let speedSlowerNotification = Notification.Name("app.rhea.mac.speedSlower")
    static let saveNotification = Notification.Name("app.rhea.mac.save")
    static let findNotification = Notification.Name("app.rhea.mac.find")
    static let increaseFontNotification = Notification.Name("app.rhea.mac.increaseFont")
    static let decreaseFontNotification = Notification.Name("app.rhea.mac.decreaseFont")
    static let resetFontNotification = Notification.Name("app.rhea.mac.resetFont")

    var body: some Scene {
        WindowGroup("Rhea") {
            RootView()
                .frame(minWidth: 600, minHeight: 400)
                .handlesExternalEvents(
                    preferring: ["rhea-main"], allowing: ["rhea-main"]
                )
                .background(WindowAccessor { window in
                    // Let vibrancy and the content flow up under the
                    // traffic lights the way Notes / Finder do.
                    window.titlebarAppearsTransparent = true
                    window.titleVisibility = NSWindow.TitleVisibility.hidden
                    window.isMovableByWindowBackground = true
                    window.styleMask.insert(NSWindow.StyleMask.fullSizeContentView)
                    window.backgroundColor = NSColor.clear
                    // Wrap the existing SwiftUI delegate so close
                    // attempts on dirty markdown buffers route through
                    // our Save / Don't Save sheet — without replacing
                    // the delegate outright, which clobbers SwiftUI's
                    // own window plumbing.
                    DirtyCloseGuard.attach(to: window)
                })
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 800, height: 600)
        .handlesExternalEvents(matching: ["rhea-main"])
        .commands {
            // Replace the default ⌘N "New Window" (one reader window
            // per process is the mental model) with ⌘N "New
            // Scratchpad" — an in-app text area the user can type
            // into and have read aloud without opening a file first.
            // URL opens still route through
            // `AppDelegateShim.application(_:open:)` which reuses the
            // front window rather than spawning a new scene.
            CommandGroup(replacing: .newItem) {
                Button("New Scratchpad") {
                    NotificationCenter.default.post(
                        name: AppScene.newScratchpadNotification, object: nil
                    )
                }
                .keyboardShortcut("N", modifiers: [.command])
            }

            CommandGroup(after: .newItem) {
                Button("Open File…") {
                    NotificationCenter.default.post(
                        name: AppScene.openFileNotification, object: nil
                    )
                }
                .keyboardShortcut("O", modifiers: [.command])

                Divider()

                Button("Save") {
                    NotificationCenter.default.post(
                        name: AppScene.saveNotification, object: nil
                    )
                }
                .keyboardShortcut("S", modifiers: [.command])
            }

            // Edit menu: place Find after the Pasteboard group (Cut /
            // Copy / Paste / Delete / Select All), which SwiftUI always
            // emits for the standard menu. `.textEditing` and
            // `.saveItem` are document-app placements that this scene
            // doesn't generate, so anchoring there silently drops the
            // entries — that bit us in 4-29.
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find…") {
                    NotificationCenter.default.post(
                        name: AppScene.findNotification, object: nil
                    )
                }
                .keyboardShortcut("F", modifiers: [.command])
            }

            CommandGroup(after: CommandGroupPlacement.importExport) {
                Button("Export Audiobook…") {
                    NotificationCenter.default.post(
                        name: AppScene.exportNotification, object: nil
                    )
                }
                .keyboardShortcut("E", modifiers: [.command, .shift])

                Button("Show Exports") {
                    NotificationCenter.default.post(
                        name: AppScene.showExportsNotification, object: nil
                    )
                }
                .keyboardShortcut("J", modifiers: [.command, .shift])
            }

            // View menu — font size adjustments for the non-PDF
            // readers (Markdown, EPUB, Scratchpad). PDFs use PDFKit's
            // own zoom and ignore these. Bound to the conventional
            // browser/Notes shortcuts: ⌘+ grows, ⌘- shrinks, ⌘0 resets.
            CommandGroup(after: .toolbar) {
                Button("Increase Font Size") {
                    NotificationCenter.default.post(
                        name: AppScene.increaseFontNotification, object: nil
                    )
                }
                .keyboardShortcut("+", modifiers: [.command])

                Button("Decrease Font Size") {
                    NotificationCenter.default.post(
                        name: AppScene.decreaseFontNotification, object: nil
                    )
                }
                .keyboardShortcut("-", modifiers: [.command])

                Button("Reset Font Size") {
                    NotificationCenter.default.post(
                        name: AppScene.resetFontNotification, object: nil
                    )
                }
                .keyboardShortcut("0", modifiers: [.command])
            }

            CommandGroup(replacing: .help) {
                Button("Show Welcome Tour…") {
                    NotificationCenter.default.post(
                        name: .rheaShowOnboarding, object: nil
                    )
                }
            }

            CommandMenu("Playback") {
                Button("Play / Pause") {
                    NotificationCenter.default.post(
                        name: AppScene.playPauseNotification, object: nil
                    )
                }
                .keyboardShortcut(.space, modifiers: [])

                Divider()

                Button("Previous Sentence") {
                    NotificationCenter.default.post(
                        name: AppScene.prevSentenceNotification, object: nil
                    )
                }
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button("Next Sentence") {
                    NotificationCenter.default.post(
                        name: AppScene.nextSentenceNotification, object: nil
                    )
                }
                .keyboardShortcut(.rightArrow, modifiers: [])

                Divider()

                Button("Speed Up") {
                    NotificationCenter.default.post(
                        name: AppScene.speedFasterNotification, object: nil
                    )
                }
                .keyboardShortcut("]", modifiers: [.command])

                Button("Slow Down") {
                    NotificationCenter.default.post(
                        name: AppScene.speedSlowerNotification, object: nil
                    )
                }
                .keyboardShortcut("[", modifiers: [.command])
            }
        }
    }
}
