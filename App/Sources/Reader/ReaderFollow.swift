import SwiftUI
import AppKit

// MARK: - Follow state

/// Tracks whether a reader auto-scrolls to keep the spoken sentence in
/// view ("follow mode") or stays where the user manually scrolled.
/// Shared by every format's reader so the behavior is identical.
///
/// Spotify-lyrics model: while following, the viewport tracks the
/// highlight on each sentence change. The moment the user scrolls by
/// hand, ``userDidScroll()`` turns following off and the viewport stays
/// put — playback and the highlight keep going underneath. The floating
/// ``JumpToCurrentButton`` calls ``jumpToCurrent()`` to scroll back and
/// resume following. There is no idle auto-re-engage: once the user
/// scrolls away, only an explicit action returns to following.
@Observable
@MainActor
final class ReaderFollowState {
    /// True = auto-scroll tracks the spoken sentence. False = the user
    /// has taken manual control; the viewport won't move on its own.
    private(set) var isFollowing: Bool = true

    /// Bumped to request a single scroll-to-highlight. The reader's
    /// `updateNSView` compares this against the token it last honored and
    /// scrolls once when they differ — the bridge from a SwiftUI button
    /// tap to an imperative AppKit scroll.
    private(set) var jumpToken: Int = 0

    /// The user scrolled by hand. Turns follow mode off; idempotent so
    /// the stream of live-scroll notifications doesn't churn state.
    func userDidScroll() {
        if isFollowing { isFollowing = false }
    }

    /// Resume following and ask the reader to scroll to the highlight
    /// now. Used by the jump button, the Play/Resume edge, and
    /// "read from here" — anywhere the viewport should snap back even
    /// when the current sentence hasn't advanced.
    func jumpToCurrent() {
        isFollowing = true
        jumpToken &+= 1
    }

    /// Reset to following without forcing a scroll. Used when a new
    /// document loads, where there's no current sentence to jump to yet.
    func resumeFollowing() {
        isFollowing = true
    }

    /// Whether the floating jump button should be visible: only when the
    /// user has scrolled away AND there's a current sentence to return
    /// to. Pure function so it's unit-testable without a live view.
    static func shouldShowJumpButton(isFollowing: Bool, hasActiveSentence: Bool) -> Bool {
        !isFollowing && hasActiveSentence
    }
}

// MARK: - Live-scroll detection

/// Watches an `NSScrollView` for user-initiated live scrolling
/// (trackpad, scroll wheel, scrollbar-knob drag) and runs a callback.
/// Programmatic `scrollRangeToVisible` does NOT post the live-scroll
/// notifications, so this never fires for the reader's own auto-scroll —
/// no "is this my own scroll?" guard is required.
///
/// Known limitation: keyboard scrolling (Page Up/Down, arrows) doesn't
/// post live-scroll notifications, so it won't flip out of follow mode.
final class ReaderScrollObserver {
    private var token: NSObjectProtocol?

    /// Begin observing `scrollView`, replacing any previous observation.
    func attach(to scrollView: NSScrollView, onUserScroll: @MainActor @escaping () -> Void) {
        detach()
        token = NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { _ in
            // Delivered on the main queue, so asserting main-actor
            // isolation here is safe.
            MainActor.assumeIsolated { onUserScroll() }
        }
    }

    func detach() {
        if let token {
            NotificationCenter.default.removeObserver(token)
            self.token = nil
        }
    }

    deinit { detach() }
}

// MARK: - Jump-to-current button

/// Floating pill shown at the bottom of a reader when the user has
/// scrolled away from the spoken sentence. Tapping it scrolls back to
/// the highlight and resumes follow mode. Renders nothing while
/// following or when there's no active sentence.
struct JumpToCurrentButton: View {
    let followState: ReaderFollowState
    let player: SpeechPlayer

    var body: some View {
        let show = ReaderFollowState.shouldShowJumpButton(
            isFollowing: followState.isFollowing,
            hasActiveSentence: player.state.sentenceIndex != nil
        )
        Group {
            if show {
                Button {
                    followState.jumpToCurrent()
                } label: {
                    Label("Jump to current", systemImage: "scope")
                        .font(ReadAloudTTSFont.ui(12).weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.readAloudTTSAccent)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityLabel("Jump to current line")
                .accessibilityHint("Scrolls back to the sentence being read and resumes following")
            }
        }
        .animation(.easeOut(duration: 0.2), value: show)
    }
}
