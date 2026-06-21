import SwiftUI
import KeyboardShortcuts

/// Settings tab for the "read aloud from anywhere" global shortcut.
/// Hosts the rebindable recorder plus the clipboard-restore toggle and
/// a short explainer about the selection-vs-clipboard behaviour.
struct ShortcutsSettingsView: View {
    @Bindable var settings = SpeechSettings.shared

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder(
                    "Read selection from anywhere:",
                    name: .readSelection
                )
            } header: {
                Text("Global Shortcuts")
            } footer: {
                Text("Read selection (default ⌘⇧E) speaks your current selection, or your clipboard if that's blocked.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(
                    "Restore clipboard after reading selection",
                    isOn: $settings.restoreClipboardAfterReading
                )
            } header: {
                Text("Clipboard")
            } footer: {
                Text("Reading your selection works by briefly copying it. Leave this on to put your previous clipboard contents back afterward.")
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(Self.ocrLanguages, id: \.code) { lang in
                    Toggle(lang.name, isOn: ocrLanguage(lang.code))
                }
            } header: {
                Text("Image OCR Languages")
            } footer: {
                Text("Languages to look for when reading an image. Pick the scripts you read; fewer, well-chosen languages recognize faster and more accurately. With none selected, the system chooses automatically.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    Button("Open Accessibility Settings…") {
                        SelectionPermission.openAccessibilitySettings()
                    }
                } label: {
                    Text("Selection reading")
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Reading the selection directly from other apps may require granting ReadAloudTTS Accessibility access in System Settings → Privacy & Security. Without it, the shortcut still reads your clipboard.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Curated OCR recognition languages offered as toggles. Codes are
    /// the BCP-47 tags Vision expects.
    private static let ocrLanguages: [(code: String, name: String)] = [
        ("en-US", "English"),
        ("zh-Hans", "Chinese (Simplified)"),
        ("zh-Hant", "Chinese (Traditional)"),
        ("ja-JP", "Japanese"),
        ("ko-KR", "Korean"),
        ("fr-FR", "French"),
        ("de-DE", "German"),
        ("es-ES", "Spanish"),
    ]

    /// Binding that toggles `code` in/out of the recognition list while
    /// preserving order (Vision treats earlier languages as higher
    /// priority).
    private func ocrLanguage(_ code: String) -> Binding<Bool> {
        Binding(
            get: { settings.ocrRecognitionLanguages.contains(code) },
            set: { isOn in
                var languages = settings.ocrRecognitionLanguages
                if isOn {
                    if !languages.contains(code) { languages.append(code) }
                } else {
                    languages.removeAll { $0 == code }
                }
                settings.ocrRecognitionLanguages = languages
            }
        )
    }
}
