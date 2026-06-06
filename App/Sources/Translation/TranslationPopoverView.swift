import SwiftUI
import Translation

/// The tap-to-translate popover. Shows the tapped word, translates it
/// on-device with Apple's Translation framework into the user's target
/// language, lets them hear it, edit the gloss, and save it to their
/// vocabulary with the surrounding sentence as context.
///
/// The gloss is editable rather than read-only so the feature stays
/// useful even when a language pair isn't downloaded yet: the user can
/// type a meaning and still save the word.
struct TranslationPopoverView: View {
    let onDismiss: () -> Void
    @State private var model: TranslationModel

    init(word: String, context: String, sourceLanguage: String?, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        _model = State(initialValue: TranslationModel(
            word: word, context: context, sourceLanguage: sourceLanguage
        ))
    }

    var body: some View {
        // An immutable reference for the @Sendable closure to capture and
        // for plain reads; `@Bindable` only supplies the TextField binding.
        let model = self.model
        @Bindable var boundModel = model
        return VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            glossSection(model: boundModel)
            if !model.context.isEmpty {
                Text(model.context)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(16)
        .frame(width: 320)
        .translationTask(model.configuration) { @Sendable session in
            // The closure is @Sendable (nonisolated), so `session` stays
            // out of the main-actor region; translate here within the
            // task, then hand the plain string result to the model.
            let translated = try? await session.translate(model.word).targetText
            await model.apply(translated)
        }
        .onAppear { model.start() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(model.word)
                .font(.title2)
                .fontWeight(.semibold)
                .textSelection(.enabled)
            Spacer()
            Button {
                WordPronouncer.shared.speak(model.word, language: model.sourceLanguage)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
            }
            .buttonStyle(.borderless)
            .help("Hear it spoken")
        }
    }

    private func glossSection(model: TranslationModel) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(model.languageLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.phase == .loading {
                    ProgressView().controlSize(.small)
                }
            }
            TextField("Translation", text: $model.gloss, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
            if model.phase == .unavailable, model.gloss.isEmpty {
                Text("On-device translation for this pair isn’t ready. Type a meaning to save it, or download the language in System Settings › General › Language & Region › Translation Languages.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel", action: onDismiss)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button(model.saved ? "Saved" : "Save to Vocabulary") {
                model.save()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(550))
                    onDismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.saved || model.gloss.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

/// Main-actor state behind the popover. A reference type so the
/// `@Sendable` translation closure can capture it (a `@MainActor` class is
/// implicitly Sendable) without dragging the SwiftUI view in. The lookup
/// inputs are `nonisolated let`s so the off-actor closure can read the
/// word without hopping.
@MainActor
@Observable
final class TranslationModel {
    nonisolated let word: String
    nonisolated let context: String
    nonisolated let sourceLanguage: String?
    nonisolated let targetLanguage: String

    var gloss: String = ""
    var phase: Phase = .loading
    var configuration: TranslationSession.Configuration?
    var saved = false

    enum Phase { case loading, ready, unavailable }

    init(word: String, context: String, sourceLanguage: String?) {
        self.word = word
        self.context = context
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = LearningSettings.shared.targetLanguage
    }

    var languageLine: String {
        let source = sourceLanguage.map { LearningSettings.displayName(for: $0) } ?? "Auto"
        let target = LearningSettings.displayName(for: targetLanguage)
        return "\(source) → \(target)"
    }

    /// Kick off translation by handing the framework a configuration.
    func start() {
        configuration = TranslationSession.Configuration(
            source: sourceLanguage.map { Locale.Language(identifier: $0) },
            target: Locale.Language(identifier: targetLanguage)
        )
    }

    /// Apply the off-actor translation result. Doesn't clobber a gloss the
    /// user already started typing.
    func apply(_ text: String?) {
        if let text, gloss.isEmpty { gloss = text }
        phase = (text == nil) ? .unavailable : .ready
    }

    func save() {
        let entry = VocabEntry(
            front: word,
            back: gloss.trimmingCharacters(in: .whitespacesAndNewlines),
            context: context,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )
        VocabularyStore.shared.add(entry)
        saved = true
    }
}
