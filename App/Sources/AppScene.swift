import SwiftUI

struct AppScene: Scene {
    /// Menu commands need a reference to the current RootView to
    /// invoke its flows. NotificationCenter keeps command→view
    /// plumbing decoupled so the command can originate from any
    /// window without threading bindings through the hierarchy.
    static let exportNotification = Notification.Name("app.rhea.mac.export")
    static let playPauseNotification = Notification.Name("app.rhea.mac.playPause")
    static let nextSentenceNotification = Notification.Name("app.rhea.mac.nextSentence")
    static let prevSentenceNotification = Notification.Name("app.rhea.mac.prevSentence")
    static let openFileNotification = Notification.Name("app.rhea.mac.openFile")
    static let speedFasterNotification = Notification.Name("app.rhea.mac.speedFaster")
    static let speedSlowerNotification = Notification.Name("app.rhea.mac.speedSlower")

    var body: some Scene {
        WindowGroup("Rhea") {
            RootView()
                .frame(minWidth: 600, minHeight: 400)
                .handlesExternalEvents(
                    preferring: ["rhea-main"], allowing: ["rhea-main"]
                )
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 800, height: 600)
        .handlesExternalEvents(matching: ["rhea-main"])
        .commands {
            // Kill the default ⌘N "New Window" — one reader window
            // per process is the whole mental model. URL opens route
            // through `AppDelegateShim.application(_:open:)` which
            // reuses the front window rather than spawning a new
            // scene.
            CommandGroup(replacing: .newItem) { }

            CommandGroup(after: .newItem) {
                Button("Open File…") {
                    NotificationCenter.default.post(
                        name: AppScene.openFileNotification, object: nil
                    )
                }
                .keyboardShortcut("O", modifiers: [.command])
            }

            CommandGroup(after: CommandGroupPlacement.importExport) {
                Button("Export Audiobook…") {
                    NotificationCenter.default.post(
                        name: AppScene.exportNotification, object: nil
                    )
                }
                .keyboardShortcut("E", modifiers: [.command, .shift])
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
