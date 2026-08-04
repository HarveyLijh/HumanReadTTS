import Foundation
import Observation

/// Tracks whether the user has seen the welcome tour and which
/// step they're on when the window is open. Persists a completed
/// version number to `UserDefaults` so future releases can
/// re-show a fresh tour when the steps change materially —
/// compare `completedVersion` against `currentVersion` at launch.
///
/// Using a shared instance keeps the RootView launch gate, the
/// Settings "Show Welcome Tour" button, and the welcome window
/// itself in sync without threading bindings.
@Observable
@MainActor
final class OnboardingState {
    static let shared = OnboardingState()

    /// Bump this when the tour's step content meaningfully
    /// changes — users with a lower `completedVersion` will see
    /// the tour again on next launch.
    static let currentVersion = 1

    private(set) var completedVersion: Int = 0

    /// Zero-based step index the welcome window should render.
    /// Reset to 0 each time the window is freshly presented so
    /// "Show Welcome Tour" from Settings always starts at the
    /// beginning regardless of where the user skipped last time.
    var step: Int = 0

    /// Total number of steps the view renders. Kept on the model
    /// (not hard-coded in the view) so `step` bounds checks and
    /// dot indicators read from a single source of truth.
    let totalSteps: Int = 6

    private let defaults: UserDefaults
    private let completedKey = "app.humanreadtts.mac.onboarding.completedVersion.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.completedVersion = defaults.integer(forKey: completedKey)
    }

    var needsToShow: Bool {
        completedVersion < Self.currentVersion
    }

    /// Called when the user completes the tour or dismisses it.
    /// Either path counts as "seen" — the tour is optional and
    /// re-openable from Settings, so a Skip doesn't need to keep
    /// nagging on every launch.
    func markCompleted() {
        completedVersion = Self.currentVersion
        defaults.set(completedVersion, forKey: completedKey)
    }

    /// Reset to step 0 before presenting. Used by both the
    /// launch-time auto-open and the Settings button so the
    /// window always opens on the welcome slide.
    func prepareForPresentation() {
        step = 0
    }

    func advance() {
        step = min(totalSteps - 1, step + 1)
    }

    func back() {
        step = max(0, step - 1)
    }
}
