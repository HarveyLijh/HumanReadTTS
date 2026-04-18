import SwiftUI

/// Dedicated Settings tab for `SkipRule`. Users see the three
/// built-in rules enabled by default (bracketed numeric citations,
/// LaTeX \cite commands, cite:key markers) and can add any number
/// of custom regex patterns on top.
///
/// Editing is kept inline — each row has a toggle, a name field, a
/// pattern field, and a trash button (disabled for built-ins; they
/// can be toggled off but not deleted so the safe defaults are
/// always recoverable). The "Try it on…" area lives below the list
/// and lets the user paste a sample sentence to see exactly what
/// would be stripped at speak time, which is the fastest way to
/// debug a tricky pattern without starting playback.
struct SkipRulesSettingsView: View {
    @Bindable var settings = SpeechSettings.shared

    @State private var sampleInput: String = "See Smith et al. [12] and \\cite{jones2019} — described in cite:doe."
    @State private var newName: String = ""
    @State private var newPattern: String = ""

    var body: some View {
        Form {
            Section {
                ForEach($settings.skipRules) { $rule in
                    ruleRow($rule)
                }
            } header: {
                Text("Rules")
            } footer: {
                Text("Matches are removed from what the synthesizer speaks. The visible document is unchanged. Invalid patterns are highlighted; they’re silently ignored at speak time.")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 8) {
                    TextField("Name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Regex pattern", text: $newPattern)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Button("Add") { addNewRule() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canAddNewRule)
                }
            } header: {
                Text("Add a custom rule")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $sampleInput)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 60, maxHeight: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                        )
                    Text("After skip rules:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(preview)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                }
            } header: {
                Text("Try it on a sentence")
            }
        }
        .formStyle(.grouped)
    }

    private var preview: String {
        ResearchCleanup.clean(
            sampleInput,
            stripCitations: settings.stripCitations,
            skipRules: settings.skipRules
        )
    }

    private var canAddNewRule: Bool {
        let trimmedName = newName.trimmingCharacters(in: .whitespaces)
        let trimmedPattern = newPattern.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedPattern.isEmpty else { return false }
        return (try? NSRegularExpression(pattern: trimmedPattern)) != nil
    }

    private func addNewRule() {
        let trimmedName = newName.trimmingCharacters(in: .whitespaces)
        let trimmedPattern = newPattern.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedPattern.isEmpty else { return }
        let rule = SkipRule(
            name: trimmedName,
            pattern: trimmedPattern,
            isEnabled: true,
            isBuiltIn: false
        )
        settings.skipRules.append(rule)
        newName = ""
        newPattern = ""
    }

    @ViewBuilder
    private func ruleRow(_ rule: Binding<SkipRule>) -> some View {
        let isValid = rule.wrappedValue.compiles
        HStack(spacing: 8) {
            Toggle("", isOn: rule.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Name", text: rule.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .disabled(rule.wrappedValue.isBuiltIn)

                HStack(spacing: 6) {
                    if !isValid {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 10))
                    }
                    TextField("Regex pattern", text: rule.pattern)
                        .textFieldStyle(.plain)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(isValid ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                        .disabled(rule.wrappedValue.isBuiltIn)
                }
            }

            Spacer(minLength: 4)

            if rule.wrappedValue.isBuiltIn {
                Text("Built-in")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            } else {
                Button {
                    deleteRule(rule.wrappedValue.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Delete this rule")
            }
        }
        .padding(.vertical, 2)
    }

    private func deleteRule(_ id: UUID) {
        settings.skipRules.removeAll { $0.id == id && !$0.isBuiltIn }
    }
}
