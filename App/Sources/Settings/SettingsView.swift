import SwiftUI
import AVFoundation

/// Standard macOS Settings window. Opens with ⌘, for free because
/// it lives in the `Settings` scene declared in `RheaApp`.
///
/// Per-voice memory (remembering speed/pitch separately for each
/// voice) is deferred — most users want one global pace that
/// follows them regardless of which voice they pick. We can revisit
/// when the Kokoro and Qwen3-TTS voices land in M2.1 / M3.1 and
/// "this voice is better at fast playback" preferences become more
/// meaningful.
struct SettingsView: View {
    @Bindable var settings = SpeechSettings.shared

    var body: some View {
        TabView {
            playbackTab
                .tabItem { Label("Playback", systemImage: "play.circle") }
                .tag(0)

            ModelsSettingsView()
                .tabItem { Label("Models", systemImage: "cube.box") }
                .tag(1)
        }
        .frame(width: 520, height: 420)
    }

    private var playbackTab: some View {
        Form {
            Section {
                Picker("Voice", selection: $settings.voiceIdentifier) {
                    Text("Auto (by language)").tag(Optional<String>.none)

                    if !KokoroEngine.shared.voices.isEmpty {
                        Section("Kokoro (on-device, English)") {
                            ForEach(KokoroEngine.shared.voices) { voice in
                                Text(voice.displayName).tag(Optional(voice.id))
                            }
                        }
                    }

                    ForEach(voicesByLanguage, id: \.language) { group in
                        Section("System · \(group.language)") {
                            ForEach(group.voices, id: \.identifier) { voice in
                                Text(voice.name).tag(Optional(voice.identifier))
                            }
                        }
                    }
                }
                .help("'Auto' picks a voice per sentence using the system language detector.")
            } header: {
                Text("Voice")
            } footer: {
                if KokoroEngine.shared.voices.isEmpty {
                    Text("Download Kokoro from the Models tab to unlock studio-quality on-device English voices.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Kokoro voices run entirely on-device. Chinese bilingual voices arrive with Qwen3-TTS in a future update.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent {
                    HStack(spacing: 12) {
                        Slider(value: $settings.rate, in: 0.5...2.5, step: 0.05)
                        Text(String(format: "%.2fx", settings.rate))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                } label: {
                    Text("Speed")
                }

                LabeledContent {
                    HStack(spacing: 12) {
                        Slider(value: $settings.pitchMultiplier, in: 0.5...2.0, step: 0.05)
                        Text(String(format: "%.2fx", settings.pitchMultiplier))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                } label: {
                    Text("Pitch")
                }
            } header: {
                Text("Pace")
            } footer: {
                Text("Changes apply at the next sentence boundary, so the current sentence finishes naturally.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset to defaults", role: .destructive) {
                    settings.reset()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var voicesByLanguage: [VoiceLanguageGroup] {
        let grouped = Dictionary(grouping: AVSpeechSynthesisVoice.speechVoices()) {
            $0.language
        }
        return grouped
            .map { VoiceLanguageGroup(language: $0.key, voices: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.language < $1.language }
    }

    private struct VoiceLanguageGroup {
        let language: String
        let voices: [AVSpeechSynthesisVoice]
    }
}
