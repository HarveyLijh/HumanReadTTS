import Foundation
import MediaPlayer
import Observation

/// Publishes the current read to the system **Now Playing** surface
/// (Control Center, the lock screen, the menu-bar Now Playing module)
/// and wires the hardware transport — `MPRemoteCommandCenter`'s
/// play / pause / next / previous / stop, which also back the F7/F8/F9
/// media keys and AirPods controls when ReadAloudTTS is the active
/// Now-Playing app.
///
/// This is the *system-integration* layer only. The in-window transport
/// bar is a separate concern (task 04-17). Both bind to the same
/// `SpeechPlayer` public API; this type never mutates playback except
/// in response to a remote command.
///
/// macOS has no `AVAudioSession`, so the playback state the system shows
/// will not be inferred — `MPNowPlayingInfoCenter.playbackState` is set
/// explicitly on every refresh. Now-Playing *eligibility* comes from the
/// app's existing audio output.
///
/// Scope note (PR1): the observed player is the menu-bar player that
/// backs clipboard / selection / OCR reads. Arbitrating the card between
/// that and the document-window player is deferred (PR4); until then a
/// document read does not populate the card.
@MainActor
@Observable
final class NowPlayingController {
    static let shared = NowPlayingController()

    /// The player whose state drives the Now Playing card.
    private(set) var activePlayer: SpeechPlayer = MenuBarCommand.shared.player

    private var didActivate = false

    private init() {}

    /// Register remote-command handlers and start mirroring the active
    /// player's state into `MPNowPlayingInfoCenter`. Idempotent; call
    /// once from `applicationDidFinishLaunching`.
    func activate() {
        guard !didActivate else { return }
        didActivate = true
        registerCommands()
        beginObserving()
        refresh()
    }

    // MARK: - Observation

    /// Mirror the player into the info center, re-arming on every
    /// observed change. `refresh()` reads the player's `state`,
    /// `sentences`, and `progress` (plus the rate), so any mutation of
    /// those re-fires `onChange` and we re-arm.
    private func beginObserving() {
        withObservationTracking {
            refresh()
        } onChange: {
            Task { @MainActor [weak self] in self?.beginObserving() }
        }
    }

    /// Push the current player state to the system, or clear the card
    /// when there is nothing loaded.
    func refresh() {
        let player = activePlayer
        // Read inside the observation-tracked refresh so toggling the
        // preference re-arms and takes effect immediately.
        guard SpeechSettings.shared.showInNowPlaying else {
            clear()
            return
        }
        guard !player.sentences.isEmpty, player.state.sentenceIndex != nil else {
            clear()
            return
        }
        setCommandsEnabled(true)

        let playing: Bool
        if case .playing = player.state { playing = true } else { playing = false }

        // `progress` is read inside the observation-tracked `refresh` and
        // internally reads `SpeechSettings.shared.rate`, so a speed change
        // still re-fires the card update — no need to read `rate` here.
        let progress = player.progress
        let meta = NowPlayingMetadata(
            title: Self.title(for: player.sentences, index: progress.currentIndex),
            albumTitle: Self.appTitle,
            elapsed: progress.estimatedElapsed,
            duration: progress.estimatedElapsed + progress.estimatedRemaining,
            isPlaying: playing
        )

        let info = MPNowPlayingInfoCenter.default()
        info.nowPlayingInfo = Self.makeInfoDictionary(meta)
        info.playbackState = playing ? .playing : .paused
    }

    private func clear() {
        setCommandsEnabled(false)
        let info = MPNowPlayingInfoCenter.default()
        info.nowPlayingInfo = nil
        info.playbackState = .stopped
    }

    /// Enable the transport commands only when there is content to act
    /// on. While disabled, the system routes the hardware media keys to
    /// the next eligible Now-Playing app (Music / Spotify) instead of us
    /// swallowing them with `.commandFailed` from an idle reader.
    private func setCommandsEnabled(_ enabled: Bool) {
        let center = MPRemoteCommandCenter.shared()
        for command in [
            center.togglePlayPauseCommand, center.playCommand, center.pauseCommand,
            center.nextTrackCommand, center.previousTrackCommand, center.stopCommand,
        ] {
            command.isEnabled = enabled
        }
    }

    // MARK: - Remote commands

    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()
        bind(center.togglePlayPauseCommand, .togglePlayPause)
        bind(center.playCommand, .play)
        bind(center.pauseCommand, .pause)
        bind(center.nextTrackCommand, .next)
        bind(center.previousTrackCommand, .previous)
        bind(center.stopCommand, .stop)
    }

    private func bind(_ command: MPRemoteCommand, _ kind: RemoteCommandKind) {
        command.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            // MPRemoteCommand delivery is NOT guaranteed on the main
            // thread (AirPods / Bluetooth-AVRCP can arrive off-main), so
            // hop to the main actor rather than assert isolation —
            // `MainActor.assumeIsolated` would hard-crash off-main.
            // Commands are only enabled when content is loaded, so a plain
            // `.success` is accurate enough for the system.
            Task { @MainActor in self.perform(kind) }
            return .success
        }
    }

    private func perform(_ kind: RemoteCommandKind) {
        let player = activePlayer
        guard Self.isEnabled(kind, sentenceCount: player.sentences.count) else { return }
        let isPlaying: Bool
        if case .playing = player.state { isPlaying = true } else { isPlaying = false }

        switch kind {
        case .togglePlayPause: player.togglePlayPause()
        case .play:  if !isPlaying { player.togglePlayPause() }
        case .pause: if isPlaying { player.togglePlayPause() }
        case .next:  player.nextSentence()
        case .previous: player.previousSentence()
        case .stop:  player.stop()
        }
        refresh()
    }

    // MARK: - Pure mapping (unit-tested without a live info center)

    static let appTitle = "ReadAloudTTS"

    /// Maps player-derived metadata to the `MPNowPlayingInfoCenter`
    /// dictionary. Elapsed/duration are already wall-clock seconds (the
    /// speed multiplier is baked into `SpeechPlayer.progress`), so the
    /// system clock advances at 1x while playing and freezes at 0 while
    /// paused. Feeding the user's multiplier into the rate would
    /// double-count it and drift the displayed time between updates.
    static func makeInfoDictionary(_ meta: NowPlayingMetadata) -> [String: Any] {
        [
            MPMediaItemPropertyTitle: meta.title,
            MPMediaItemPropertyAlbumTitle: meta.albumTitle,
            MPMediaItemPropertyPlaybackDuration: meta.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: meta.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: meta.isPlaying ? 1.0 : 0.0,
        ]
    }

    /// A short, single-line title for the card: the current sentence,
    /// trimmed and truncated. Falls back to the app name.
    static func title(for sentences: [Sentence], index: Int) -> String {
        guard sentences.indices.contains(index) else { return appTitle }
        let raw = sentences[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return appTitle }
        let limit = 64
        guard raw.count > limit else { return raw }
        return raw.prefix(limit).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// Every transport command needs loaded content to act on.
    static func isEnabled(_ kind: RemoteCommandKind, sentenceCount: Int) -> Bool {
        sentenceCount > 0
    }
}

/// The transport commands the system can send us.
enum RemoteCommandKind: Equatable, Sendable {
    case togglePlayPause
    case play
    case pause
    case next
    case previous
    case stop
}

/// Value type carrying everything the Now Playing card shows — kept
/// separate from `MPNowPlayingInfoCenter` so the mapping is pure and
/// testable.
struct NowPlayingMetadata: Equatable {
    var title: String
    var albumTitle: String
    var elapsed: TimeInterval
    var duration: TimeInterval
    var isPlaying: Bool
}
