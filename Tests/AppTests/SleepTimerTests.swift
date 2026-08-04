import XCTest
@testable import HumanReadTTS

@MainActor
final class SleepTimerTests: XCTestCase {

    private func makePlayer(loaded: Bool = true) -> SpeechPlayer {
        let player = SpeechPlayer()
        if loaded {
            player.load([
                Sentence(text: "One.", blockIndex: 0, offsetInBlock: 0, lengthInBlock: 4),
                Sentence(text: "Two.", blockIndex: 0, offsetInBlock: 5, lengthInBlock: 4),
            ])
        }
        return player
    }

    private func makeTimer(_ player: SpeechPlayer) -> SleepTimer {
        SleepTimer(playerProvider: { player })
    }

    func test_armMinutes_setsModeAndFireDate() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let timer = makeTimer(makePlayer())
        timer.arm(.minutes(10), now: now)
        XCTAssertEqual(timer.mode, .minutes(10))
        XCTAssertTrue(timer.isArmed)
        XCTAssertEqual(timer.remainingSeconds(now: now), 600)
        XCTAssertEqual(timer.fireDate, now.addingTimeInterval(600))
    }

    func test_cancel_disarmsAndClearsBoundaryFlag() {
        let player = makePlayer()
        let timer = makeTimer(player)
        timer.arm(.endOfSentence)
        XCTAssertTrue(player.stopAtNextSentenceBoundary)

        timer.cancel()
        XCTAssertEqual(timer.mode, .off)
        XCTAssertFalse(timer.isArmed)
        XCTAssertNil(timer.fireDate)
        XCTAssertFalse(player.stopAtNextSentenceBoundary,
                       "cancelling must remove a pending end-of-sentence stop")
    }

    func test_endOfSentence_flipsPlayerBoundaryFlag() {
        let player = makePlayer()
        let timer = makeTimer(player)
        timer.arm(.endOfSentence)
        XCTAssertEqual(timer.mode, .endOfSentence)
        XCTAssertNil(timer.remainingSeconds(), "end-of-sentence has no countdown")
        XCTAssertTrue(player.stopAtNextSentenceBoundary)
    }

    func test_load_clearsStaleBoundaryFlag() {
        let player = makePlayer()
        makeTimer(player).arm(.endOfSentence)
        XCTAssertTrue(player.stopAtNextSentenceBoundary)
        // Opening a new document must not inherit the pending stop.
        player.load([Sentence(text: "New.", blockIndex: 0, offsetInBlock: 0, lengthInBlock: 4)])
        XCTAssertFalse(player.stopAtNextSentenceBoundary)
    }

    func test_extend_pushesFireDateAndAccumulatesMinutes() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let timer = makeTimer(makePlayer())
        timer.arm(.minutes(10), now: now)
        timer.extend(by: 5, now: now)
        XCTAssertEqual(timer.mode, .minutes(15))
        XCTAssertEqual(timer.fireDate, now.addingTimeInterval(900))
        XCTAssertEqual(timer.remainingSeconds(now: now), 900)
    }

    func test_extend_noopWhenNotMinutesMode() {
        let timer = makeTimer(makePlayer())
        timer.arm(.endOfSentence)
        timer.extend(by: 5)
        XCTAssertEqual(timer.mode, .endOfSentence, "extend only applies to minute timers")
    }

    func test_fire_disarms_andIsNoopOnIdlePlayer() {
        let player = makePlayer()
        let timer = makeTimer(player)
        timer.arm(.minutes(5))
        timer.fire()
        XCTAssertEqual(timer.mode, .off)
        XCTAssertNil(timer.fireDate)
        XCTAssertEqual(player.state, .idle, "firing on an idle player just disarms")
    }

    func test_remainingSeconds_clampsToZeroAfterFireDate() {
        let now = Date(timeIntervalSince1970: 3_000_000)
        let timer = makeTimer(makePlayer())
        timer.arm(.minutes(1), now: now)
        XCTAssertEqual(timer.remainingSeconds(now: now.addingTimeInterval(120)), 0)
    }
}
