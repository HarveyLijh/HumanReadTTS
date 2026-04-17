import SwiftUI

struct AppScene: Scene {
    /// Menu commands need a reference to the current RootView to
    /// invoke its export flow. We key the NotificationCenter
    /// pathway off this so the command can originate from any
    /// window without us plumbing bindings through the hierarchy.
    static let exportNotification = Notification.Name("app.rhea.mac.export")

    var body: some Scene {
        WindowGroup("Rhea") {
            RootView()
                .frame(minWidth: 600, minHeight: 400)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandGroup(after: CommandGroupPlacement.importExport) {
                Button("Export Audiobook…") {
                    NotificationCenter.default.post(
                        name: AppScene.exportNotification, object: nil
                    )
                }
                .keyboardShortcut("E", modifiers: [.command, .shift])
            }
        }
    }
}
