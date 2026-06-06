import Foundation
import Observation

/// Stops playback after a chosen delay — minute presets, or "at the end
/// of the current sentence." Pauses (keeps position) rather than
/// stopping, so the user can resume where they dozed off.
///
/// The minute countdown is derived from a fire `Date` rather than a
/// tick counter, so `remainingSeconds` stays correct across view churn
/// and app backgrounding. The action and the clock are split (`fire()`,
/// explicit `now:`) so the whole state machine is unit-testable without
/// waiting real time.
@MainActor
@Observable
final class SleepTimer {
    static let shared = SleepTimer()

    enum Mode: Equatable, Sendable {
        case off
        case minutes(Int)
        case endOfSentence
    }

    /// Minute durations offered in the menu.
    static let presets = [5, 10, 15, 30, 45, 60]

    private(set) var mode: Mode = .off
    /// Instant a minutes-mode timer will fire; nil otherwise.
    private(set) var fireDate: Date?

    private var task: Task<Void, Never>?
    private let playerProvider: () -> SpeechPlayer

    /// The player the timer acts on. Defaults to the Now Playing active
    /// player so the timer pauses whatever is currently reading.
    private var player: SpeechPlayer { playerProvider() }

    init(playerProvider: @escaping () -> SpeechPlayer = { NowPlayingController.shared.activePlayer }) {
        self.playerProvider = playerProvider
    }

    var isArmed: Bool { mode != .off }

    /// Seconds until a minutes-mode fire, or nil when off /
    /// end-of-sentence.
    func remainingSeconds(now: Date = Date()) -> Int? {
        guard let fireDate else { return nil }
        return max(0, Int(fireDate.timeIntervalSince(now).rounded()))
    }

    func arm(_ requested: Mode, now: Date = Date()) {
        cancel()
        switch requested {
        case .off:
            break
        case .endOfSentence:
            // Honored in SpeechPlayer.didFinishCurrent; the flag is
            // cleared by load(), so it can't leak into a later document.
            player.stopAtNextSentenceBoundary = true
            mode = .endOfSentence
        case .minutes(let minutes):
            let seconds = max(1, minutes) * 60
            mode = .minutes(minutes)
            fireDate = now.addingTimeInterval(TimeInterval(seconds))
            scheduleCountdown(seconds: seconds)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        mode = .off
        fireDate = nil
        player.stopAtNextSentenceBoundary = false
    }

    /// Push a running minutes timer out by `minutes`. No-op unless a
    /// minutes timer is armed.
    func extend(by minutes: Int, now: Date = Date()) {
        guard case .minutes(let current) = mode, let fireDate else { return }
        let newFire = fireDate.addingTimeInterval(TimeInterval(minutes * 60))
        self.fireDate = newFire
        mode = .minutes(current + minutes)
        scheduleCountdown(seconds: max(1, Int(newFire.timeIntervalSince(now).rounded())))
    }

    private func scheduleCountdown(seconds: Int) {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.fire()
        }
    }

    /// Pause the active player and disarm. Exposed so tests can exercise
    /// the action without waiting out the countdown.
    func fire() {
        if case .minutes = mode, player.state.isPlaying {
            player.togglePlayPause()
        }
        task = nil
        mode = .off
        fireDate = nil
    }
}
