import SwiftUI

@main
struct RheaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegateShim.self) private var appDelegate
    @State private var menuBar = MenuBarCommand.shared

    var body: some Scene {
        AppScene()

        Window("Exports", id: "exports") {
            ExportQueueView(coordinator: ExportCoordinator.shared)
        }
        .defaultSize(width: 620, height: 420)

        OnboardingScene()

        Settings {
            SettingsView()
        }

        MenuBarExtra("Rhea", systemImage: "waveform") {
            Button("Read Clipboard") {
                menuBar.readClipboard()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button(menuBar.playPauseLabel) {
                menuBar.player.togglePlayPause()
            }
            .disabled(menuBar.player.sentences.isEmpty)

            Button("Stop") {
                menuBar.player.stop()
            }
            .disabled(menuBar.player.sentences.isEmpty)

            Divider()

            Button("Open Rhea") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.title == "Rhea" }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }

            Divider()

            Button("Quit Rhea") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
