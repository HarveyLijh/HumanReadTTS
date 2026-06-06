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
                KeyboardShortcuts.Recorder(
                    "Read a screenshot (OCR):",
                    name: .readScreenshot
                )
            } header: {
                Text("Global Shortcuts")
            } footer: {
                Text("Read selection (default ⌘⇧E) speaks your current selection, or your clipboard if that's blocked. Read a screenshot (default ⌘⇧2) runs OCR on an image on the clipboard, so you can screenshot an area with ⌃⇧⌘4 and hear it.")
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
