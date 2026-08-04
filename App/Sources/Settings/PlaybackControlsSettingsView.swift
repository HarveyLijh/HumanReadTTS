import SwiftUI
import AppKit

/// Playback-transport settings: system Now Playing integration, the
/// sleep-timer default, and the reading queue. Binds to the shared
/// `SpeechSettings` and `ReadingQueue` singletons so the menu-bar reader
/// and Control Center reflect changes immediately.
struct PlaybackControlsSettingsView: View {
    @Bindable private var speech = SpeechSettings.shared
    @Bindable private var queue = ReadingQueue.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show reads in Now Playing & media keys", isOn: $speech.showInNowPlaying)
            } header: {
                Text("System Integration")
            } footer: {
                Text("Publishes the current read to Control Center and the menu-bar Now Playing widget, and lets F7/F8/F9 and AirPods controls drive playback when HumanReadTTS was the last app to play audio.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Default duration", selection: $speech.sleepTimerMinutes) {
                    ForEach(SleepTimer.presets, id: \.self) { minutes in
                        Text("\(minutes) minutes").tag(minutes)
                    }
                }
            } header: {
                Text("Sleep Timer")
            } footer: {
                Text("Preselected in the menu-bar Sleep Timer submenu. The timer is never armed automatically on launch.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Auto-advance to the next item", isOn: $queue.autoAdvance)

                if queue.isEmpty {
                    Text("The queue is empty. Add reads with “Queue Clipboard Text” below or from the menu bar.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(queue.items) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "text.alignleft")
                                .foregroundStyle(.secondary)
                            Text(item.title)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                queue.remove(item.id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove from queue")
                        }
                    }
                }

                HStack {
                    Button("Queue Clipboard Text") {
                        if let text = NSPasteboard.general.string(forType: .string) {
                            MenuBarCommand.shared.enqueueText(text)
                        }
                    }
                    if !queue.isEmpty {
                        Button("Clear Queue", role: .destructive) { queue.clear() }
                    }
                }
            } header: {
                Text("Reading Queue")
            } footer: {
                Text("Reads play in order. With auto-advance on, the next item starts when the current read finishes.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
