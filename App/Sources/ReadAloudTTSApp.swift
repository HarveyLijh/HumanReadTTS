import SwiftUI

@main
struct ReadAloudTTSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegateShim.self) private var appDelegate
    @State private var menuBar = MenuBarCommand.shared
    @State private var sleepTimer = SleepTimer.shared

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

        MenuBarExtra {
            Button("Read Selection") {
                menuBar.readSelectionOrClipboard()
            }

            Button("Read Screenshot Text") {
                menuBar.readClipboardImage()
            }

            Button(menuBar.playPauseLabel) {
                menuBar.player.togglePlayPause()
            }
            .disabled(menuBar.player.sentences.isEmpty)

            Button("Stop") {
                menuBar.player.stop()
            }
            .disabled(menuBar.player.sentences.isEmpty)

            Menu(sleepTimerLabel) {
                ForEach(SleepTimer.presets, id: \.self) { minutes in
                    Button {
                        sleepTimer.arm(.minutes(minutes))
                    } label: {
                        if sleepTimer.mode == .minutes(minutes) {
                            Label("\(minutes) minutes", systemImage: "checkmark")
                        } else {
                            Text("\(minutes) minutes")
                        }
                    }
                }
                Button("End of current sentence") {
                    sleepTimer.arm(.endOfSentence)
                }
                .disabled(!menuBar.player.state.isPlaying)
                if sleepTimer.isArmed {
                    Divider()
                    Button("Turn Off Sleep Timer") { sleepTimer.cancel() }
                }
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
        } label: {
            Image(systemName: menuBar.isSpeaking ? "waveform.circle.fill" : "waveform")
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var sleepTimerLabel: String {
        switch sleepTimer.mode {
        case .off: return "Sleep Timer"
        case .endOfSentence: return "Sleep Timer · end of sentence"
        case .minutes(let minutes): return "Sleep Timer · \(minutes) min"
        }
    }
}
