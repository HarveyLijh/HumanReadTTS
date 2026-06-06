import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings → Learning: the tap-to-translate gesture, the target
/// language, and the saved-vocabulary list with Anki export. Binds the
/// shared `LearningSettings` and `VocabularyStore` so words saved from the
/// translation popover appear here immediately.
struct LearningSettingsView: View {
    @Bindable private var settings = LearningSettings.shared
    @Bindable private var vocab = VocabularyStore.shared

    @State private var exportError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Option-double-click a word to translate", isOn: $settings.tapToTranslateEnabled)

                Picker("Translate into", selection: $settings.targetLanguage) {
                    ForEach(LearningSettings.offeredLanguages, id: \.self) { code in
                        Text(LearningSettings.displayName(for: code)).tag(code)
                    }
                }
                .disabled(!settings.tapToTranslateEnabled)
            } header: {
                Text("Tap to Translate")
            } footer: {
                Text("Hold Option and double-click any word while reading to see its translation, hear it spoken, and save it to your vocabulary. Translation runs on-device with Apple's Translation; the first time you use a language pair, macOS may prompt a one-time download.")
                    .foregroundStyle(.secondary)
            }

            Section {
                if vocab.isEmpty {
                    Text("No saved words yet. Turn on tap-to-translate above, then Option-double-click a word while reading to add it here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vocab.entries) { entry in
                        VocabRow(entry: entry) { vocab.remove(entry.id) }
                    }
                }
            } header: {
                HStack {
                    Text("Saved Vocabulary")
                    Spacer()
                    if !vocab.isEmpty {
                        Text("\(vocab.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !vocab.isEmpty {
                Section {
                    HStack {
                        Button("Export to Anki (CSV)…") { exportCSV() }
                        Button("Clear All", role: .destructive) { vocab.clear() }
                    }
                    if let exportError {
                        Text(exportError)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("The CSV imports into Anki with Front, Back, Context, and a language tag, no column mapping needed.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func exportCSV() {
        exportError = nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "vocabulary.csv"
        panel.canCreateDirectories = true
        panel.title = "Export Vocabulary"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(vocab.exportCSV().utf8).write(to: url)
        } catch {
            exportError = "Couldn’t write the file: \(error.localizedDescription)"
        }
    }
}

/// One saved word: term over its gloss, with a remove button. Pulled out
/// so the list stays readable and the row layout is reused if a detail
/// view lands later.
private struct VocabRow: View {
    let entry: VocabEntry
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.front)
                    .fontWeight(.medium)
                if !entry.back.isEmpty {
                    Text(entry.back)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if !entry.context.isEmpty {
                    Text(entry.context)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove from vocabulary")
        }
        .padding(.vertical, 2)
    }
}
