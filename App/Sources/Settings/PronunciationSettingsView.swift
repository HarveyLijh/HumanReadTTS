import SwiftUI

/// Settings tab for managing the pronunciation dictionary.
struct PronunciationSettingsView: View {
    @Bindable var dict: PronunciationDictionary = .shared

    @State private var newTerm: String = ""
    @State private var newPhonetic: String = ""

    var body: some View {
        Form {
            Section {
                if dict.entries.isEmpty {
                    Text("No custom pronunciations yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                } else {
                    ForEach(dict.entries) { entry in
                        HStack {
                            Text(entry.term)
                                .font(.system(.body, design: .serif))
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.tertiary)
                            Text(entry.phonetic)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(role: .destructive) {
                                dict.remove(id: entry.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("Dictionary")
            } footer: {
                Text("Terms are matched case-insensitively on whole words. Substitutions apply to both the system synthesizer and Kokoro.")
                    .foregroundStyle(.secondary)
            }

            Section("Add term") {
                HStack(spacing: 8) {
                    TextField("Term (e.g. PDF)", text: $newTerm)
                        .textFieldStyle(.roundedBorder)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.tertiary)
                    TextField("Spoken as (e.g. P D F)", text: $newPhonetic)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        dict.add(term: newTerm, phonetic: newPhonetic)
                        newTerm = ""
                        newPhonetic = ""
                    }
                    .disabled(
                        newTerm.trimmingCharacters(in: .whitespaces).isEmpty ||
                        newPhonetic.trimmingCharacters(in: .whitespaces).isEmpty
                    )
                }
            }
        }
        .formStyle(.grouped)
    }
}
