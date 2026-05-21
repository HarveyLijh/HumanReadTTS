import SwiftUI

@main
struct ReadAloudTTSApp: App {
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

        MenuBarExtra("ReadAloudTTS", systemImage: "waveform") {
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

            Button("Open ReadAloudTTS") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.title == "ReadAloudTTS" }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }

            Divider()

            Button("Quit ReadAloudTTS") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
