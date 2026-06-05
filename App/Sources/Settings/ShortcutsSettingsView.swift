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
                Text("Global Shortcut")
            } footer: {
                Text("Press this from any app to read text aloud. ReadAloudTTS reads your current selection where macOS allows it, and otherwise falls back to whatever you last copied. Default: ⌘⇧E.")
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
}
