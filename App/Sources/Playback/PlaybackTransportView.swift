import SwiftUI
import AVFoundation
import AppKit

/// The capsule-shaped transport bar anchored at the bottom of the
/// reader. Replaces the old corner play button. Every control
/// surfaces its consequence: tooltips on skip buttons show "≈Ns",
/// the speed popover footer notes "Applies at next sentence", and
/// the voice menu shows engine badges + download-required rows for
/// voices whose model isn't on disk.
///
/// Granularity is one sentence throughout — the neural engines
/// can't mid-sentence resume, and Speechify's desktop reader uses
/// the same sentence-snap convention. We surface this honestly
/// with a "≈N seconds" tooltip rather than pretending to scrub at
/// second granularity.
@MainActor
struct PlaybackTransportView: View {
    @Bindable var player: SpeechPlayer
    @Bindable var settings = SpeechSettings.shared

    @Environment(\.openSettings) private var openSettings

    @State private var scrubIndex: Double?
    @State private var showingSpeedPopover = false
    @State private var showingVoicePopover = false
    @State private var showingSkipPopover = false
    @State private var kokoroReady = false
    @State private var qwenReady = false

    var body: some View {
        // ViewThatFits picks the widest layout that fits. The HUD
        // centers inside its container and caps at 720pt so huge
        // windows don't stretch controls apart. Below 720pt it
        // progressively drops the time readout, then the voice
        // label, then the speed label — every layout keeps
        // transport (skip/play/skip) + scrubber + gear.
        HStack {
            Spacer(minLength: 0)
            ViewThatFits(in: .horizontal) {
                fullLayout
                noTimeLayout
                compactLayout
                tinyLayout
            }
            .frame(maxWidth: 720)
            Spacer(minLength: 0)
        }
        .task {
            async let k: Void = KokoroEngine.shared.loadIfNeeded()
            async let q: Void = QwenEngine.shared.loadIfNeeded()
            _ = await (k, q)
            kokoroReady = true
            qwenReady = true
        }
        .onChange(of: settings.skipRules) { _, _ in
            // Any toggle / edit of skip rules must invalidate the
            // prefetched next sentence; otherwise the next sentence
            // was synthesized against the previous rule set and the
            // change wouldn't land until the user skipped or
            // restarted. The current sentence already being spoken
            // stays as-is (spec: "applies at next sentence").
            player.invalidateNeuralPrefetch()
        }
    }

    private var fullLayout: some View {
        hudRow {
            skipBack
            playPause
            skipForward
            scrubber
            timeReadout
            skipChip
            speedChip
            voiceChip(style: .full)
            settingsButton
        }
    }

    private var noTimeLayout: some View {
        hudRow {
            skipBack
            playPause
            skipForward
            scrubber
            skipChip
            speedChip
            voiceChip(style: .short)
            settingsButton
        }
    }

    private var compactLayout: some View {
        hudRow {
            skipBack
            playPause
            skipForward
            scrubber(minWidth: 120)
            speedChip
            voiceChip(style: .iconOnly)
            settingsButton
        }
    }

    /// Last-resort layout for very narrow windows. Drops the speed
    /// chip entirely (still reachable via ⌘] / ⌘[ or the voice
    /// menu's parent Settings link). Keeps the transport, scrubber,
    /// voice, and gear — the must-haves.
    private var tinyLayout: some View {
        hudRow {
            skipBack
            playPause
            skipForward
            scrubber(minWidth: 80)
            voiceChip(style: .iconOnly)
            settingsButton
        }
    }

    @ViewBuilder
    private func hudRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    private var isDisabled: Bool { player.sentences.isEmpty }

    // MARK: skip buttons

    private var skipBack: some View {
        Button { player.previousSentence() } label: {
            Image(systemName: "backward.end.fill")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help("Previous sentence · \(secondsEstimate(for: .previous))")
        .keyboardShortcut(.leftArrow, modifiers: [.command])
    }

    private var skipForward: some View {
        Button { player.nextSentence() } label: {
            Image(systemName: "forward.end.fill")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help("Next sentence · \(secondsEstimate(for: .next))")
        .keyboardShortcut(.rightArrow, modifiers: [.command])
    }

    // MARK: play/pause

    private var playPause: some View {
        Button { player.togglePlayPause() } label: {
            Image(systemName: player.state.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.rheaAccent, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .help(player.state.isPlaying ? "Pause" : "Play")
    }

    // MARK: scrubber

    private var scrubber: some View { scrubber(minWidth: 180) }

    private func scrubber(minWidth: CGFloat) -> some View {
        let progress = player.progress
        let total = max(Double(progress.total - 1), 0)
        let bindingValue = scrubIndex ?? Double(progress.currentIndex)
        let isDragging = scrubIndex != nil
        return Slider(
            value: Binding(
                get: { bindingValue },
                set: { newValue in
                    // Hold the drag locally so the UI doesn't flicker
                    // back to the player's live index during drag.
                    scrubIndex = newValue
                }
            ),
            in: 0...max(total, 1),
            step: 1,
            onEditingChanged: { editing in
                guard !editing, let target = scrubIndex else { return }
                let idx = Int(target.rounded())
                player.playFromSentence(idx)
                scrubIndex = nil
            }
        )
        .controlSize(.small)
        .frame(minWidth: minWidth, maxWidth: 280)
        .disabled(isDisabled || progress.total < 2)
        .help(scrubberTooltip(at: bindingValue))
        .overlay(alignment: .top) {
            if isDragging, progress.total > 1 {
                // Floating preview capsule that tracks the thumb's
                // rough position. The thumb is hidden under the user's
                // cursor during drag; this bubble above the track is
                // where the user's eye actually goes.
                scrubberPreviewBubble(at: bindingValue, total: total)
                    .offset(y: -32)
            }
        }
    }

    /// Bubble rendered above the scrubber during drag. We lay it out
    /// inside a GeometryReader so its horizontal offset tracks the
    /// slider's thumb instead of always sitting centred — otherwise
    /// a drag to either edge makes the preview drift away from the
    /// thumb by half a bubble width, which is visually confusing.
    private func scrubberPreviewBubble(
        at value: Double, total: Double
    ) -> some View {
        let idx = Int(value.rounded())
        let clamped = max(0, min(idx, player.sentences.count - 1))
        let sentence = player.sentences.indices.contains(clamped)
            ? player.sentences[clamped] : nil
        let preview = sentence.map { String($0.text.prefix(80)) } ?? ""
        return GeometryReader { geo in
            let fraction = total > 0 ? value / total : 0
            let thumbX = geo.size.width * fraction
            VStack(alignment: .leading, spacing: 2) {
                Text("Sentence \(clamped + 1) of \(player.sentences.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(preview)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: 300, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
            )
            .fixedSize(horizontal: false, vertical: true)
            .offset(x: max(0, min(thumbX - 150, geo.size.width - 160)))
        }
        .frame(height: 44)
        .allowsHitTesting(false)
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
    }

    private func scrubberTooltip(at value: Double) -> String {
        let idx = Int(value.rounded())
        guard idx >= 0, idx < player.sentences.count else {
            return "Jump to sentence"
        }
        let preview = player.sentences[idx].text.prefix(60)
        return "Sentence \(idx + 1) of \(player.sentences.count) — “\(preview)…”"
    }

    // MARK: time readout

    private var timeReadout: some View {
        let progress = player.progress
        return Text("\(format(progress.estimatedElapsed)) / \(format(progress.estimatedElapsed + progress.estimatedRemaining))")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(minWidth: 82)
            .help("Estimated — based on words per minute from your reading stats.")
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: skip-rules chip

    /// Small chip that surfaces the count of active skip rules and
    /// opens a per-rule toggle popover. Keeps the important
    /// transparency signal ("text is being stripped before speech")
    /// at a glance without having to open Settings.
    private var skipChip: some View {
        let enabled = settings.skipRules.filter(\.isEnabled).count
        return Button {
            showingSkipPopover.toggle()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "scissors")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(enabled)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(enabled == 0 ? .secondary : .primary)
            .frame(minHeight: 26)
            .padding(.horizontal, 8)
            .background(Color.primary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(skipChipTooltip(enabled: enabled))
        .popover(isPresented: $showingSkipPopover, arrowEdge: .bottom) {
            SkipRulesPopover(settings: settings)
        }
    }

    private func skipChipTooltip(enabled: Int) -> String {
        if enabled == 0 { return "No skip rules active." }
        if enabled == 1 { return "1 skip rule active — click to toggle." }
        return "\(enabled) skip rules active — click to toggle."
    }

    // MARK: speed chip

    private var speedChip: some View {
        Button {
            showingSpeedPopover.toggle()
        } label: {
            Text(String(format: "%.2g×", settings.rate))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(minWidth: 40, minHeight: 26)
                .padding(.horizontal, 6)
                .background(Color.primary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Playback speed · ⌘] faster · ⌘[ slower")
        .popover(isPresented: $showingSpeedPopover, arrowEdge: .bottom) {
            SpeedPopover(settings: settings, player: player)
        }
    }

    // MARK: voice chip

    private enum VoiceChipStyle { case full, short, iconOnly }

    @ViewBuilder
    private func voiceChip(style: VoiceChipStyle) -> some View {
        Button {
            showingVoicePopover.toggle()
        } label: {
            HStack(spacing: 4) {
                switch style {
                case .full:
                    Text(voiceLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 130, alignment: .leading)
                case .short:
                    Text(voiceShortLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 90, alignment: .leading)
                case .iconOnly:
                    Image(systemName: voiceIconName)
                        .font(.system(size: 12))
                        .foregroundStyle(isInFallback ? Color.orange : .primary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 26)
            .padding(.horizontal, 8)
            .background(Color.primary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Voice: \(voiceLabel) · click to switch mid-read")
        .popover(isPresented: $showingVoicePopover, arrowEdge: .bottom) {
            VoicePopover(
                player: player,
                settings: settings,
                kokoroReady: kokoroReady,
                qwenReady: qwenReady
            )
        }
    }

    /// Stripped-down voice label for the mid-size layout: drops the
    /// parenthetical descriptor so "Ryan (narrator male, EN / ZH)"
    /// becomes "Ryan", keeping the chip predictable in width.
    private var voiceShortLabel: String {
        let full = voiceLabel
        if let paren = full.firstIndex(of: "(") {
            return full[..<paren].trimmingCharacters(in: .whitespaces)
        }
        return full
    }

    /// The label shown in the voice chip. Reflects what's *actually*
    /// playing — so after a Kokoro/Qwen engine fallback, the chip
    /// flips to "System" with the system-voice badge instead of
    /// continuing to claim the user's chosen neural voice. The most
    /// recent `SwitchEvent.engineFallback` makes the chip honest.
    private var voiceLabel: String {
        if isInFallback { return "System (fallback)" }
        if let id = settings.voiceIdentifier {
            if id.hasPrefix("kokoro:") {
                return KokoroEngine.shared.voices
                    .first(where: { $0.id == id })?.displayName ?? "Kokoro"
            }
            if id.hasPrefix("qwen:") {
                return QwenEngine.shared.voices
                    .first(where: { $0.id == id })?.displayName ?? "Qwen"
            }
            return AVSpeechSynthesisVoice(identifier: id)?.name ?? "System"
        }
        return "Auto"
    }

    /// The SF Symbol for the voice chip icon (compact layout). Same
    /// fallback-reflective logic as `voiceLabel`.
    private var voiceIconName: String {
        if isInFallback { return "waveform.slash" }
        return "person.wave.2"
    }

    /// True when the most recent switch event was a fallback and
    /// the user hasn't explicitly picked a different voice since.
    /// Cleared as soon as the user dismisses the banner or changes
    /// voice.
    private var isInFallback: Bool {
        guard let event = player.lastSwitchEvent else { return false }
        if case .engineFallback = event.kind { return true }
        return false
    }

    // MARK: settings gear

    private var settingsButton: some View {
        Button {
            openSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 12))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help("Open Settings")
    }

    // MARK: seconds-estimate helper

    private enum Direction { case next, previous }

    private func secondsEstimate(for direction: Direction) -> String {
        let idx = player.state.sentenceIndex ?? 0
        let target: Int
        switch direction {
        case .next: target = idx
        case .previous: target = max(idx - 1, 0)
        }
        guard target >= 0, target < player.sentences.count else {
            return "≈15s"
        }
        let words = player.sentences[target].text.roughWordCount
        // Prefer the user's measured reading wpm (settles at ~130 to
        // ~180 depending on voice) when available — falls back to the
        // 165 wpm baseline for fresh installs where ReadingStats
        // hasn't built up a sample yet.
        let statsWpm = ReadingStats.shared.wordsPerMinute
        let baseWpm = (statsWpm > 0 ? statsWpm : 165.0) * settings.rate
        let seconds = Double(words) / max(baseWpm, 1) * 60.0
        return "≈\(Int(seconds.rounded()))s"
    }
}

// MARK: - Speed popover

@MainActor
private struct SpeedPopover: View {
    @Bindable var settings: SpeechSettings
    let player: SpeechPlayer

    private let presets: [Double] = [0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playback speed").font(.headline)

            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { preset in
                    Button {
                        player.setRate(preset)
                    } label: {
                        Text(String(format: "%.2g×", preset))
                            .font(.system(size: 11, design: .monospaced))
                            .frame(minWidth: 42, minHeight: 26)
                            .background(
                                Capsule().fill(
                                    abs(settings.rate - preset) < 0.01
                                        ? Color.rheaAccent.opacity(0.25)
                                        : Color.primary.opacity(0.06)
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Button {
                    player.setRate(max(0.5, settings.rate - 0.1))
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.bordered)

                Slider(
                    value: Binding(
                        get: { settings.rate },
                        set: { player.setRate($0) }
                    ),
                    in: 0.5...4.0,
                    step: 0.05
                )

                Button {
                    player.setRate(min(4.0, settings.rate + 0.1))
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.bordered)
            }

            Text(String(format: "Current: %.2f× · Applies at next sentence.", settings.rate))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 320)
    }
}

// MARK: - Voice popover

@MainActor
private struct VoicePopover: View {
    let player: SpeechPlayer
    @Bindable var settings: SpeechSettings
    let kokoroReady: Bool
    let qwenReady: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                section(title: "Auto") {
                    row(
                        label: "Auto (pick by language)",
                        identifier: nil,
                        badge: "Smart",
                        enabled: true
                    )
                }

                kokoroSection
                qwenSection

                systemVoicesSection
            }
            .padding(12)
        }
        .frame(width: 320, height: 420)
    }

    @ViewBuilder
    private var kokoroSection: some View {
        switch KokoroEngine.shared.state {
        case .ready:
            if KokoroEngine.shared.voices.isEmpty {
                section(title: "Kokoro · Studio English") {
                    downloadHint(
                        message: "Kokoro loaded but no voices found. Re-download from Settings → Models."
                    )
                }
            } else {
                section(title: "Kokoro · Studio English") {
                    ForEach(KokoroEngine.shared.voices) { voice in
                        row(
                            label: voice.displayName,
                            identifier: voice.id,
                            badge: "Kokoro",
                            enabled: true
                        )
                    }
                }
            }
        case .loading:
            section(title: "Kokoro · Studio English") {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Loading Kokoro…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            section(title: "Kokoro · Studio English") {
                downloadHint(
                    message: "Kokoro load failed: \(message). Re-download from Settings → Models."
                )
            }
        case .idle:
            section(title: "Kokoro · Studio English") {
                downloadHint(
                    message: "Download Kokoro in Settings → Models to unlock 28 English voices."
                )
            }
        }
    }

    @ViewBuilder
    private var qwenSection: some View {
        switch QwenEngine.shared.state {
        case .ready:
            section(title: "Qwen3-TTS · Bilingual EN + ZH") {
                ForEach(QwenEngine.shared.voices) { voice in
                    row(
                        label: voice.displayName,
                        identifier: voice.id,
                        badge: "Qwen",
                        enabled: true
                    )
                }
            }
        case .loading:
            section(title: "Qwen3-TTS · Bilingual EN + ZH") {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Loading Qwen3-TTS…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            section(title: "Qwen3-TTS · Bilingual EN + ZH") {
                downloadHint(
                    message: "Qwen3-TTS unavailable: \(message)\n\nRe-download from Settings → Models to fix."
                )
                // Still show voices but disabled — so the user can
                // see what they're missing out on.
                ForEach(QwenEngine.shared.voices) { voice in
                    row(
                        label: voice.displayName,
                        identifier: voice.id,
                        badge: "Qwen",
                        enabled: false
                    )
                    .opacity(0.45)
                }
            }
        case .idle:
            section(title: "Qwen3-TTS · Bilingual EN + ZH") {
                downloadHint(
                    message: "Download Qwen3-TTS in Settings → Models for bilingual English + Chinese."
                )
            }
        }
    }

    @ViewBuilder
    private var systemVoicesSection: some View {
        section(title: "System voices") {
            ForEach(systemVoicesGrouped, id: \.language) { group in
                Text(group.language)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
                ForEach(group.voices, id: \.identifier) { voice in
                    row(
                        label: voice.name,
                        identifier: voice.identifier,
                        badge: "System",
                        enabled: true
                    )
                }
            }
        }
    }

    private func section<Content: View>(
        title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            content()
        }
    }

    private func row(
        label: String,
        identifier: String?,
        badge: String,
        enabled: Bool
    ) -> some View {
        let isSelected = settings.voiceIdentifier == identifier
        return Button {
            player.setVoice(identifier)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.rheaAccent : .secondary)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                Text(badge)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func downloadHint(message: String) -> some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
    }

    private var systemVoicesGrouped: [SystemVoiceGroup] {
        let grouped = Dictionary(grouping: AVSpeechSynthesisVoice.speechVoices()) {
            $0.language
        }
        return grouped
            .map { SystemVoiceGroup(language: $0.key, voices: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.language < $1.language }
    }

    private struct SystemVoiceGroup {
        let language: String
        let voices: [AVSpeechSynthesisVoice]
    }
}

// MARK: - Skip rules popover

@MainActor
private struct SkipRulesPopover: View {
    @Bindable var settings: SpeechSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Skip rules")
                    .font(.headline)
                Spacer()
                Text("\(settings.skipRules.filter(\.isEnabled).count) active")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text("Text patterns stripped from speech. Visible document unchanged.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            if settings.skipRules.isEmpty {
                Text("No rules configured. Add one in Settings → Skip Rules.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach($settings.skipRules) { $rule in
                    Toggle(isOn: $rule.isEnabled) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(rule.name)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Text(rule.pattern)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
            }

            Divider()

            Text("Changes apply at the next sentence.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(width: 320)
    }
}
