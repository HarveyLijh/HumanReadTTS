import XCTest
@testable import ReadAloudTTS

@MainActor
final class ReaderFollowStateTests: XCTestCase {

    func test_defaults_followingWithZeroToken() {
        let state = ReaderFollowState()
        XCTAssertTrue(state.isFollowing, "readers start by following the highlight")
        XCTAssertEqual(state.jumpToken, 0)
    }

    func test_userDidScroll_stopsFollowing_andIsIdempotent() {
        let state = ReaderFollowState()
        state.userDidScroll()
        XCTAssertFalse(state.isFollowing)
        let tokenAfterFirst = state.jumpToken

        // A stream of live-scroll notifications shouldn't churn state.
        state.userDidScroll()
        XCTAssertFalse(state.isFollowing)
        XCTAssertEqual(state.jumpToken, tokenAfterFirst, "scrolling never bumps the jump token")
    }

    func test_jumpToCurrent_resumesFollowing_andBumpsToken() {
        let state = ReaderFollowState()
        state.userDidScroll()

        state.jumpToCurrent()
        XCTAssertTrue(state.isFollowing)
        XCTAssertEqual(state.jumpToken, 1)

        // Each jump requests a fresh scroll, even if already following.
        state.jumpToCurrent()
        XCTAssertEqual(state.jumpToken, 2)
    }

    func test_resumeFollowing_restoresFollow_withoutForcingJump() {
        let state = ReaderFollowState()
        state.userDidScroll()

        state.resumeFollowing()
        XCTAssertTrue(state.isFollowing)
        XCTAssertEqual(
            state.jumpToken, 0,
            "resume relies on the natural sentence-change scroll, not a forced jump"
        )
    }

    func test_shouldShowJumpButton() {
        // Following: never show, even with an active sentence.
        XCTAssertFalse(ReaderFollowState.shouldShowJumpButton(
            isFollowing: true, hasActiveSentence: true
        ))
        // Not following but nothing playing: nothing to jump to.
        XCTAssertFalse(ReaderFollowState.shouldShowJumpButton(
            isFollowing: false, hasActiveSentence: false
        ))
        // Not following with an active sentence: show it.
        XCTAssertTrue(ReaderFollowState.shouldShowJumpButton(
            isFollowing: false, hasActiveSentence: true
        ))
    }
}
