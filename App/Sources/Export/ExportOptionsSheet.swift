import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Dedicated "Generate Audio for Entire Article" panel presented as
/// a sheet from `RootView`. The sheet:
///   1. Resolves the sidebar bookmark to a URL and loads sentences
///      in the background (spinner while extracting).
///   2. Lets the user pin an alternative voice / rate / pitch / format
///      for this specific job without mutating the live speech
///      settings the reader is using.
///   3. Previews an ETA derived from `ExportEstimator`, which is
///      self-calibrating once the first real export completes.
///   4. On confirm, presents an NSSavePanel for the destination and
///      enqueues the job onto the shared `ExportCoordinator` so the
///      existing HUD chip and Exports window track progress.
///
/// The sheet intentionally owns no playback state — it reads voice
/// catalogues off the shared engines and hands everything to the
/// coordinator on dismiss.
@MainActor
struct ExportOptionsSheet: View {
    let entry: LibraryEntry
    let library: Library
    let coordinator: ExportCoordinator
    let onDismiss: () -> Void

    @State private var loadState: LoadState = .loading
    @State private var sentences: [Sentence] = []
    @State private var resolvedURL: URL?

    // Form state — seeded from the user's current live-playback
    // preferences so "just use what I'm already listening with" is
    // one click away.
    @State private var voiceID: String? = SpeechSettings.shared.voiceIdentifier
    @State private var rate: Double = SpeechSettings.shared.rate
    @State private var pitch: Double = SpeechSettings.shared.pitchMultiplier
    @State private var format: AudioExportFormat = .m4a
    @State private var rangeStart: Int = 1
    @State private var rangeEnd: Int = 1

    private enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 520)
        .frame(minHeight: 520)
        .task(id: entry.id) {
            await loadSentences()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Generate Audio")
                .font(.headline)
            Text(entry.title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            loadingState
        case .failed(let message):
            failureState(message)
        case .ready:
            form
        }
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.readAloudTTSAccent)
            Text("Preparing document…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func failureState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.orange)
            Text("Couldn't load this document")
                .font(.system(size: 13, weight: .medium))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                voiceSection
                speedSection
                formatSection
                rangeSection
                etaSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    // MARK: form sections

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Voice")
            Picker("", selection: Binding<String>(
                get: { voiceID ?? autoKey },
                set: { new in voiceID = (new == autoKey) ? nil : new }
            )) {
                Text("Auto (match document language)").tag(autoKey)

                let kokoroVoices = KokoroEngine.shared.voices
                if !kokoroVoices.isEmpty {
                    Divider()
                    Section("Kokoro — neural") {
                        ForEach(kokoroVoices) { v in
                            Text(v.displayName).tag(v.id)
                        }
                    }
                }

                let qwenVoices = QwenEngine.shared.voices
                if !qwenVoices.isEmpty {
                    Divider()
                    Section("Qwen3-TTS — neural (bilingual)") {
                        ForEach(qwenVoices) { v in
                            Text(v.displayName).tag(v.id)
                        }
                    }
                }

                Divider()
                Section("System voices") {
                    ForEach(systemVoices, id: \.identifier) { voice in
                        Text("\(voice.name) · \(voice.language)")
                            .tag(voice.identifier)
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            slider(
                label: "Rate",
                value: $rate,
                range: 0.5...2.5,
                step: 0.05,
                format: { String(format: "%.2f×", $0) }
            )
            slider(
                label: "Pitch",
                value: $pitch,
                range: 0.5...2.0,
                step: 0.05,
                format: { String(format: "%.2f×", $0) }
            )
        }
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Format")
            Picker("", selection: $format) {
                ForEach(AudioExportFormat.allCases) { f in
                    Text(f.displayName).tag(f)
                }
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)
        }
    }

    private var rangeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Sentence range")
            HStack(spacing: 10) {
                rangeStepper(
                    title: "From",
                    value: $rangeStart,
                    bounds: 1...max(1, sentences.count)
                )
                rangeStepper(
                    title: "To",
                    value: $rangeEnd,
                    bounds: 1...max(1, sentences.count)
                )
                Spacer()
                Text(rangeSummary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .onChange(of: rangeStart) { _, new in
                if rangeEnd < new { rangeEnd = new }
            }
            .onChange(of: rangeEnd) { _, new in
                if rangeStart > new { rangeStart = new }
            }
        }
    }

    private var etaSection: some View {
        let selection = Array(selectedSentences)
        let eta = ExportEstimator.estimate(
            sentences: selection,
            voiceIdentifier: voiceID,
            rate: rate
        )
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "timer")
                .foregroundStyle(Color.readAloudTTSAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Estimated generation time: \(ExportEstimator.formatted(eta))")
                    .font(.system(size: 12, weight: .medium))
                Text(etaFootnote)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.readAloudTTSAccent.opacity(0.08))
        )
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { onDismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Export…") { confirmAndEnqueue() }
                .buttonStyle(.borderedProminent)
                .tint(Color.readAloudTTSAccent)
                .keyboardShortcut(.defaultAction)
                .disabled(loadState != .ready || sentences.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func slider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                sectionLabel(label)
                Spacer()
                Text(format(value.wrappedValue))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
                .tint(Color.readAloudTTSAccent)
        }
    }

    private func rangeStepper(
        title: String,
        value: Binding<Int>,
        bounds: ClosedRange<Int>
    ) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Stepper(
                value: value,
                in: bounds,
                step: 1
            ) {
                Text("\(value.wrappedValue)")
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minWidth: 36, alignment: .trailing)
            }
            .labelsHidden()
        }
    }

    private var rangeSummary: String {
        guard !sentences.isEmpty else { return "0 sentences" }
        let count = max(0, rangeEnd - rangeStart + 1)
        return "\(count) sentences · \(selectedCharCount) chars"
    }

    private var selectedCharCount: Int {
        selectedSentences.reduce(0) { $0 + $1.text.count }
    }

    private var selectedSentences: ArraySlice<Sentence> {
        guard !sentences.isEmpty else { return [] }
        let lower = max(0, min(rangeStart - 1, sentences.count - 1))
        let upper = max(lower, min(rangeEnd - 1, sentences.count - 1))
        return sentences[lower...upper]
    }

    private var etaFootnote: String {
        if ExportEstimator.isUsingDefault(voiceIdentifier: voiceID) {
            return "Based on default rates; tightens after your first export."
        }
        return "Based on measured performance from previous exports on this Mac."
    }

    private var autoKey: String { "__humanreadtts.auto" }

    private var systemVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .sorted { $0.name < $1.name }
    }

    // MARK: sentence loading

    private func loadSentences() async {
        loadState = .loading
        guard let url = library.resolve(entry) else {
            loadState = .failed("This file is no longer available at its saved location.")
            return
        }
        resolvedURL = url
        do {
            let loaded = try await ExportSentenceLoader.load(url: url)
            sentences = loaded
            rangeStart = 1
            rangeEnd = max(1, loaded.count)
            if loaded.isEmpty {
                loadState = .failed("No readable sentences found in this document.")
            } else {
                loadState = .ready
            }
        } catch let error as ExportSentenceLoader.LoadError {
            loadState = .failed(error.errorDescription ?? "Couldn't read document.")
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: enqueue

    private func confirmAndEnqueue() {
        let sliceSentences = Array(selectedSentences)
        guard !sliceSentences.isEmpty, let resolvedURL else { return }

        let suggestion = resolvedURL
            .deletingPathExtension()
            .lastPathComponent

        let panel = NSSavePanel()
        panel.title = "Save Audio Export"
        panel.nameFieldStringValue = suggestion + "." + format.fileExtension
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let response = panel.runModal()
        guard response == .OK, var dest = panel.url else { return }
        if dest.pathExtension.lowercased() != format.fileExtension {
            dest.deletePathExtension()
            dest.appendPathExtension(format.fileExtension)
        }

        let overrides = ExportOverrides(
            voiceIdentifier: voiceID,
            rate: rate,
            pitchMultiplier: pitch
        )
        coordinator.enqueue(
            sentences: sliceSentences,
            destination: dest,
            format: format,
            title: suggestion,
            overrides: overrides
        )
        onDismiss()
    }
}
