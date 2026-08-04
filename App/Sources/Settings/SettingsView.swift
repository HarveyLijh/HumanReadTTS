import SwiftUI
import AVFoundation

/// Standard macOS Settings window. Opens with ⌘, for free because
/// it lives in the `Settings` scene declared in `HumanReadTTSApp`.
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

            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "command") }
                .tag(5)

            ModelsSettingsView()
                .tabItem { Label("Models", systemImage: "cube.box") }
                .tag(1)

            PronunciationSettingsView()
                .tabItem { Label("Pronunciation", systemImage: "character.book.closed") }
                .tag(2)

            SkipRulesSettingsView()
                .tabItem { Label("Skip Rules", systemImage: "scissors") }
                .tag(3)

            AnalyticsSettingsView()
                .tabItem { Label("Analytics", systemImage: "chart.bar") }
                .tag(4)

            ReadingSettingsView()
                .tabItem { Label("Reading", systemImage: "textformat") }
                .tag(6)

            PlaybackControlsSettingsView()
                .tabItem { Label("Playback Controls", systemImage: "playpause.circle") }
                .tag(7)

            LearningSettingsView()
                .tabItem { Label("Learning", systemImage: "character.book.closed.fill") }
                .tag(8)
        }
        // Wide enough that all tab items stay on the toolbar instead of
        // collapsing the last ones into a "more items" overflow chevron.
        .frame(width: 720, height: 540)
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

                    if ModelManager.shared.isUsable(ModelCatalog.qwen3TTSSmall) {
                        Section("Qwen3-TTS (on-device, bilingual)") {
                            ForEach(QwenEngine.shared.voices) { voice in
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
                if KokoroEngine.shared.voices.isEmpty,
                   !ModelManager.shared.isUsable(ModelCatalog.qwen3TTSSmall) {
                    Text("Download Kokoro or Qwen3-TTS from the Models tab to unlock studio-quality on-device voices.")
                        .foregroundStyle(.secondary)
                } else if ModelManager.shared.isUsable(ModelCatalog.qwen3TTSSmall) {
                    Text("Qwen3-TTS is bilingual (EN + ZH) and picks per-sentence automatically when 'Auto' is selected.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Kokoro voices run entirely on-device. Download Qwen3-TTS to add bilingual English / Chinese support.")
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
                Toggle("Skip author–year citations (Smith et al., 2019)", isOn: $settings.stripCitations)
                Toggle("Skip figure and table captions", isOn: $settings.skipFigureCaptions)
            } header: {
                Text("Research PDFs")
            } footer: {
                Text("Author–year uses a curated regex that stays accurate on tricky cases; hides `Figure N:` / `Table N:` blocks when loading a PDF. For `[12]`, `\\cite{…}`, and custom patterns, see the Skip Rules tab. The visible document is unchanged.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    Button("Show Welcome Tour…") {
                        NotificationCenter.default.post(
                            name: .readAloudTTSShowOnboarding, object: nil
                        )
                    }
                } label: {
                    Text("Welcome tour")
                }
            } header: {
                Text("Help")
            } footer: {
                Text("Walk through the basics again — voice, shortcuts, and a sample document.")
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
