import SwiftUI
import AppKit
import AVFoundation

/// Five-step welcome tour shown on first launch and re-openable
/// from Settings. Lives in its own `Window` scene (see HumanReadTTSApp)
/// rather than a sheet so it can present before any document is
/// loaded and survive resizing the main window.
///
/// Keyboard map: Return advances, Esc skips, ← / → step between
/// slides. "Skip" is always visible in the top-right — the tour
/// is optional, and hiding the exit in a menu or in gray micro-
/// text is the anti-pattern Apple's HIG calls out.
struct OnboardingView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var state = OnboardingState.shared
    @State private var preview = VoicePreviewer()
    @FocusState private var rootFocused: Bool
    // Re-seed the step index to zero every time the welcome
    // window appears fresh — both the first-launch gate and
    // the Settings re-open path rely on this.

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .underWindowBackground)
                .ignoresSafeArea()
            Color.readAloudTTSSurface.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
        }
        .frame(width: 720, height: 520)
        .focusable()
        .focused($rootFocused)
        .focusEffectDisabled()
        .onAppear { rootFocused = true }
        .onDisappear {
            preview.stop()
            // Any exit path — explicit Finish, Skip, or the red
            // traffic-light — counts as "seen" so the next launch
            // goes straight to the reader.
            state.markCompleted()
        }
        .onKeyPress(.return) { advance(); return .handled }
        .onKeyPress(.escape) { skip(); return .handled }
        .onKeyPress(.rightArrow) { advance(); return .handled }
        .onKeyPress(.leftArrow) { back(); return .handled }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image("BrandIcon")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
            Text("Getting Started")
                .font(HumanReadTTSFont.ui(12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Skip") { skip() }
                .buttonStyle(.plain)
                .font(HumanReadTTSFont.ui(12))
                .foregroundStyle(.secondary)
                .help("Skip the tour (Esc). You can revisit it from Settings.")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch state.step {
            case 0: WelcomeStep()
            case 1: VoiceStep(preview: preview)
            case 2: ModelsStep()
            case 3: IntegrationsStep()
            case 4: ShortcutsStep()
            default: ReadyStep()
            }
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(state.step)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
        ))
        .animation(.easeOut(duration: 0.22), value: state.step)
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 7) {
                ForEach(0..<state.totalSteps, id: \.self) { i in
                    Circle()
                        .fill(i == state.step
                              ? Color.readAloudTTSAccent
                              : Color.secondary.opacity(0.25))
                        .frame(width: 6, height: 6)
                        .animation(.easeOut(duration: 0.18), value: state.step)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                if state.step > 0 {
                    Button("Back") { back() }
                        .buttonStyle(.bordered)
                }
                Button(primaryLabel) { advance() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.readAloudTTSAccent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var primaryLabel: String {
        switch state.step {
        case 0: return "Get Started"
        case state.totalSteps - 1: return "Start Reading"
        default: return "Continue"
        }
    }

    private func advance() {
        preview.stop()
        if state.step == state.totalSteps - 1 {
            finish()
        } else {
            state.advance()
        }
    }

    private func back() {
        preview.stop()
        state.back()
    }

    private func skip() {
        preview.stop()
        finish(loadSample: false)
    }

    /// Materialises the bundled README sample, routes it to the
    /// main window via `.readAloudTTSOpenURL` (the same notification
    /// AppDelegateShim posts for `open -a HumanReadTTS file.pdf`), then
    /// dismisses the welcome window. If the sample copy fails we
    /// still dismiss — the tour shouldn't block on disk errors.
    private func finish(loadSample: Bool = true) {
        if loadSample {
            if let url = try? OnboardingSampleLoader.prepareSampleURL() {
                NotificationCenter.default.post(
                    name: .readAloudTTSOpenURL,
                    object: nil,
                    userInfo: ["url": url]
                )
            }
        }
        // Raise the main reader window so Start Reading visibly
        // hands off to the document instead of leaving the user
        // staring at an empty desktop after the welcome window
        // closes.
        if let main = NSApp.windows.first(where: { $0.title == "HumanReadTTS" }) {
            main.makeKeyAndOrderFront(nil)
        }
        dismissWindow(id: OnboardingScene.windowID)
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 18) {
            Image("BrandIcon")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)

            VStack(spacing: 8) {
                Text("Welcome to HumanReadTTS")
                    .font(HumanReadTTSFont.serif(34, weight: .bold))
                Text("The local-first reader that speaks your documents aloud.")
                    .font(HumanReadTTSFont.ui(15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            HStack(spacing: 28) {
                BulletFeature(
                    systemImage: "lock.shield",
                    title: "Fully on-device",
                    caption: "No cloud, no account"
                )
                BulletFeature(
                    systemImage: "character.bubble",
                    title: "Bilingual",
                    caption: "English + Chinese"
                )
                BulletFeature(
                    systemImage: "square.and.arrow.down",
                    title: "Audiobook export",
                    caption: "M4A or WAV"
                )
            }
            .padding(.top, 6)
        }
    }
}

private struct VoiceStep: View {
    @Bindable var settings = SpeechSettings.shared
    let preview: VoicePreviewer

    var body: some View {
        VStack(spacing: 16) {
            StepTitle(
                icon: "speaker.wave.2",
                title: "Pick a voice",
                subtitle: "HumanReadTTS ships with your system voices out of the box. Neural voices (Kokoro, Qwen3-TTS) can be downloaded later from Settings → Models."
            )

            VStack(alignment: .leading, spacing: 12) {
                Picker("Voice", selection: $settings.voiceIdentifier) {
                    Text("Auto (by language)").tag(Optional<String>.none)
                    ForEach(systemVoices, id: \.identifier) { voice in
                        Text("\(voice.name) · \(voice.language)")
                            .tag(Optional(voice.identifier))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                HStack(spacing: 10) {
                    Button {
                        preview.toggle(
                            voiceIdentifier: settings.voiceIdentifier,
                            text: "Hello. I'm ready to read your documents aloud."
                        )
                    } label: {
                        Label(
                            preview.isSpeaking ? "Stop" : "Preview this voice",
                            systemImage: preview.isSpeaking
                                ? "stop.circle"
                                : "play.circle"
                        )
                    }
                    .buttonStyle(.bordered)

                    Text("You can change the voice any time from the transport chip or Settings.")
                        .font(HumanReadTTSFont.ui(11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .frame(maxWidth: 540)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
    }

    private var systemVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .sorted { $0.name < $1.name }
    }
}

private struct ModelsStep: View {
    @Bindable private var manager = ModelManager.shared
    @State private var downloadTasks: [String: Task<Void, Never>] = [:]

    var body: some View {
        VStack(spacing: 14) {
            StepTitle(
                icon: "sparkles",
                title: "Upgrade to neural voices",
                subtitle: "Optional, but highly recommended. Neural voices + Whisper AI alignment run fully on-device — no cloud, no account. You can skip and do this later from Settings → Models."
            )

            VStack(spacing: 10) {
                ModelDownloadRow(
                    entry: ModelCatalog.kokoro,
                    tagline: "Recommended · 28 studio-quality English voices",
                    status: manager.statuses[ModelCatalog.kokoro.id] ?? .notDownloaded,
                    onAction: { toggle(ModelCatalog.kokoro) }
                )
                ModelDownloadRow(
                    entry: ModelCatalog.qwen3TTSSmall,
                    tagline: "Optional · Bilingual English + Chinese, 6 voices",
                    status: manager.statuses[ModelCatalog.qwen3TTSSmall.id] ?? .notDownloaded,
                    onAction: { toggle(ModelCatalog.qwen3TTSSmall) }
                )
                ModelDownloadRow(
                    entry: ModelCatalog.whisperBase,
                    tagline: "AI alignment · word-level highlight sync for neural voices",
                    status: manager.statuses[ModelCatalog.whisperBase.id] ?? .notDownloaded,
                    onAction: { toggle(ModelCatalog.whisperBase) }
                )
            }
            .frame(maxWidth: 540)

            Text("Downloads continue in the background — feel free to keep going.")
                .font(HumanReadTTSFont.ui(11))
                .foregroundStyle(.secondary)
        }
    }

    private func toggle(_ entry: ModelEntry) {
        let status = manager.statuses[entry.id] ?? .notDownloaded
        switch status {
        case .downloading:
            // Cancelling mid-stream isn't supported by the
            // downloader yet — treat the button as a no-op
            // rather than pretending it stops the job.
            return
        case .ready:
            manager.delete(entry)
        case .notDownloaded, .failed:
            downloadTasks[entry.id]?.cancel()
            downloadTasks[entry.id] = Task { await manager.download(entry) }
        }
    }
}

private struct ModelDownloadRow: View {
    let entry: ModelEntry
    let tagline: String
    let status: ModelManager.Status
    let onAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(HumanReadTTSFont.ui(13, weight: .semibold))
                HStack(spacing: 6) {
                    Text(tagline)
                        .font(HumanReadTTSFont.ui(11))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(HumanReadTTSFont.ui(11))
                        .foregroundStyle(.secondary)
                    Text(sizeLabel)
                        .font(HumanReadTTSFont.ui(11))
                        .foregroundStyle(.secondary)
                }
                if case .failed(let message) = status {
                    Text(message)
                        .font(HumanReadTTSFont.ui(10))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Spacer()

            actionControl
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var actionControl: some View {
        switch status {
        case .notDownloaded:
            Button("Download", action: onAction)
                .buttonStyle(.borderedProminent)
                .tint(Color.readAloudTTSAccent)
                .controlSize(.small)
        case .downloading(let completed, let total):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("\(completed)/\(total)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        case .ready:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .font(HumanReadTTSFont.ui(12, weight: .medium))
                .foregroundStyle(Color.readAloudTTSAccent)
                .labelStyle(.titleAndIcon)
        case .failed:
            Button("Retry", action: onAction)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private var iconName: String {
        switch status {
        case .ready: return "waveform.circle.fill"
        case .downloading: return "arrow.down.circle"
        case .failed: return "exclamationmark.triangle"
        case .notDownloaded: return "waveform.circle"
        }
    }

    private var iconColor: Color {
        switch status {
        case .ready: return Color.readAloudTTSAccent
        case .failed: return .orange
        default: return .secondary
        }
    }

    private var sizeLabel: String {
        "\(entry.approximateSizeMB) MB"
    }
}

private struct IntegrationsStep: View {
    @State private var showCopiedHint = false

    var body: some View {
        VStack(spacing: 14) {
            StepTitle(
                icon: "gearshape.2",
                title: "macOS integrations",
                subtitle: "HumanReadTTS runs in the sandbox with no Accessibility or Microphone access needed. Two optional one-time setup steps make it feel native."
            )

            VStack(spacing: 10) {
                IntegrationRow(
                    icon: "keyboard",
                    title: "Enable the \u{201c}Read with HumanReadTTS\u{201d} Service",
                    caption: "Highlight text in any app → Services → Read with HumanReadTTS. macOS hides new services until you enable them once.",
                    buttonLabel: "Open Keyboard Settings",
                    action: openServicesSettings
                )

                IntegrationRow(
                    icon: "lock.open",
                    title: "First-launch Gatekeeper (you're past it)",
                    caption: "If you ever move HumanReadTTS between Macs, right-click → Open the first time to clear the quarantine flag. Later launches are plain double-click.",
                    buttonLabel: nil,
                    action: {}
                )
            }
            .frame(maxWidth: 560)

            Text("Everything else — TTS, file drop, audio export — works out of the box.")
                .font(HumanReadTTSFont.ui(11))
                .foregroundStyle(.secondary)
        }
    }

    /// Opens the Keyboard → Keyboard Shortcuts pane in System
    /// Settings. On Ventura+ the Services subpane doesn't have its
    /// own URL, so we land on Keyboard Shortcuts and let the user
    /// click "Services" in the sidebar.
    private func openServicesSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct IntegrationRow: View {
    let icon: String
    let title: String
    let caption: String
    let buttonLabel: String?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color.readAloudTTSAccent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(HumanReadTTSFont.ui(13, weight: .semibold))
                Text(caption)
                    .font(HumanReadTTSFont.ui(11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if let label = buttonLabel {
                Button(label, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .fixedSize()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

private struct ShortcutsStep: View {
    private let shortcuts: [(keys: String, action: String)] = [
        ("Space", "Play / Pause"),
        ("←  →", "Previous / Next sentence"),
        ("⌘ ]  ⌘ [", "Speed up / slow down"),
        ("⌘ O", "Open a file"),
        ("⌘ ⇧ E", "Export as audiobook"),
        ("⌘ ⇧ J", "Show export queue"),
        ("⌘ ⇧ S", "Read clipboard (anywhere)"),
        ("⌘ ,", "Settings"),
    ]

    var body: some View {
        VStack(spacing: 14) {
            StepTitle(
                icon: "keyboard",
                title: "Keyboard shortcuts",
                subtitle: "The essentials. Drag any PDF, Markdown, or EPUB onto the window to open it."
            )

            VStack(spacing: 0) {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { idx, entry in
                    HStack {
                        Text(entry.keys)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(minWidth: 120, alignment: .leading)
                        Text(entry.action)
                            .font(HumanReadTTSFont.ui(12))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    if idx < shortcuts.count - 1 {
                        Divider().opacity(0.3)
                    }
                }
            }
            .frame(maxWidth: 460)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
    }
}

private struct ReadyStep: View {
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.readAloudTTSAccent.opacity(0.14))
                    .frame(width: 72, height: 72)
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.readAloudTTSAccent)
            }

            VStack(spacing: 8) {
                Text("You're all set")
                    .font(HumanReadTTSFont.serif(28, weight: .bold))
                Text("Press Start Reading to open HumanReadTTS's README as a sample. When you're done, drag any PDF, Markdown, or EPUB onto the window to read your own.")
                    .font(HumanReadTTSFont.ui(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(icon: "cursorarrow.click.2",
                           text: "Double-click any word to start from there.")
                FeatureRow(icon: "arrow.down.doc",
                           text: "⌘⇧E renders the whole document to M4A or WAV.")
                FeatureRow(icon: "tray.full",
                           text: "⌘⇧J opens the export queue — jobs run in the background.")
            }
            .padding(14)
            .frame(maxWidth: 460)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )

            Text("Want to see this tour again? Settings → Playback → Show Welcome Tour.")
                .font(HumanReadTTSFont.ui(11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Small building blocks

private struct StepTitle: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.readAloudTTSAccent)
                .frame(height: 36)
            Text(title)
                .font(HumanReadTTSFont.serif(26, weight: .bold))
            Text(subtitle)
                .font(HumanReadTTSFont.ui(13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
        }
    }
}

private struct BulletFeature: View {
    let systemImage: String
    let title: String
    let caption: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Color.readAloudTTSAccent)
                .frame(height: 24)
            Text(title)
                .font(HumanReadTTSFont.ui(12, weight: .semibold))
            Text(caption)
                .font(HumanReadTTSFont.ui(11))
                .foregroundStyle(.secondary)
        }
        .frame(width: 110)
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.readAloudTTSAccent)
                .frame(width: 20)
            Text(text)
                .font(HumanReadTTSFont.ui(13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Voice preview

/// Tiny self-contained speaker for the onboarding voice step.
/// Uses AVSpeechSynthesizer directly — the main SpeechPlayer
/// pipeline depends on a loaded document, which the welcome
/// window doesn't have and shouldn't require. Class (not struct)
/// so it can own the synthesizer and delegate stop callbacks.
@Observable
@MainActor
final class VoicePreviewer {
    private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private var delegate: PreviewDelegate!

    init() {
        delegate = PreviewDelegate { [weak self] in
            self?.isSpeaking = false
        }
        synthesizer.delegate = delegate
    }

    func toggle(voiceIdentifier: String?, text: String) {
        if isSpeaking {
            stop()
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        if let voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }
}

private final class PreviewDelegate: NSObject, AVSpeechSynthesizerDelegate {
    let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async { [onFinish] in onFinish() }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async { [onFinish] in onFinish() }
    }
}

// MARK: - Scene

/// Welcome window scene. Declared as its own top-level `Window`
/// (not a `WindowGroup`) because the tour is a singleton — we
/// never want two welcome windows stacked. The id is used by
/// `openWindow` / `dismissWindow` across the app.
struct OnboardingScene: Scene {
    static let windowID = "welcome"

    var body: some Scene {
        Window("Welcome to HumanReadTTS", id: Self.windowID) {
            OnboardingView()
                .background(WindowAccessor { window in
                    window.titlebarAppearsTransparent = true
                    window.titleVisibility = .hidden
                    window.styleMask.insert(.fullSizeContentView)
                    window.isMovableByWindowBackground = true
                    window.backgroundColor = .clear
                    // Hide zoom — a fixed-size welcome window is
                    // the Mac convention (Craft, Raycast, Things
                    // all do this). Close and minimise stay on
                    // so the user can always dismiss.
                    window.standardWindowButton(.zoomButton)?.isHidden = true
                })
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 720, height: 520)
        .commandsRemoved()
    }
}
