import XCTest
@testable import HumanReadTTS

/// Pure-logic coverage of the new `SpeechPlayer` surface added in
/// PR1: `playFromSentence`, `setVoice`, `setRate`, and the
/// `progress` readout. No AVFoundation or neural engines are
/// exercised here — the player is loaded with sentences but never
/// played, so we avoid touching `AVSpeechSynthesizer` on the test
/// host.
@MainActor
final class SpeechPlayerProgressTests: XCTestCase {

    private var player: SpeechPlayer!
    private var originalVoice: String?

    override func setUp() async throws {
        try await super.setUp()
        player = SpeechPlayer()
        originalVoice = SpeechSettings.shared.voiceIdentifier
    }

    override func tearDown() async throws {
        player = nil
        SpeechSettings.shared.voiceIdentifier = originalVoice
        try await super.tearDown()
    }

    // MARK: progress

    func test_progress_emptyQueue_returnsZero() {
        let p = player.progress
        XCTAssertEqual(p.total, 0)
        XCTAssertEqual(p.currentIndex, 0)
        XCTAssertEqual(p.fraction, 0)
        XCTAssertEqual(p.estimatedElapsed, 0, accuracy: 0.001)
        XCTAssertEqual(p.estimatedRemaining, 0, accuracy: 0.001)
    }

    func test_progress_singleSentence_fractionIsZero() {
        player.load([Self.sentence("Hello world.", index: 0)])
        let p = player.progress
        XCTAssertEqual(p.total, 1)
        XCTAssertEqual(p.currentIndex, 0)
        // Fraction uses total-1 as the denominator; a single sentence
        // is both start and end — report 0, not NaN.
        XCTAssertEqual(p.fraction, 0)
    }

    func test_progress_sumsElapsedAndRemainingWords() {
        let sentences = [
            Self.sentence("One two three four five.", index: 0),       // 5 words
            Self.sentence("Six seven eight.", index: 1),                 // 3 words
            Self.sentence("Nine ten.", index: 2),                         // 2 words
        ]
        player.load(sentences)
        let p = player.progress
        XCTAssertEqual(p.total, 3)
        // Idle + cursor at 0 means zero elapsed, 10 words remaining.
        XCTAssertEqual(p.currentIndex, 0)
        let totalSeconds = p.estimatedElapsed + p.estimatedRemaining
        XCTAssertGreaterThan(totalSeconds, 0)
        XCTAssertEqual(p.estimatedElapsed, 0, accuracy: 0.001)
    }

    // MARK: playFromSentence

    func test_playFromSentence_emptyQueue_isNoOp() {
        player.playFromSentence(0)
        XCTAssertEqual(player.state, .idle)
    }

    func test_playFromSentence_clampsNegativeIndex() {
        player.load([
            Self.sentence("First.", index: 0),
            Self.sentence("Second.", index: 1),
        ])
        player.playFromSentence(-5)
        // After the call the engine is attempting to speak index 0.
        XCTAssertEqual(player.state.sentenceIndex, 0)
    }

    func test_playFromSentence_clampsOverflowIndex() {
        player.load([
            Self.sentence("Only one.", index: 0),
        ])
        player.playFromSentence(99)
        XCTAssertEqual(player.state.sentenceIndex, 0)
    }

    // MARK: setVoice

    func test_setVoice_whenIdle_persistsAndEmitsEvent() {
        SpeechSettings.shared.voiceIdentifier = nil
        player.setVoice("kokoro:af_sky")
        XCTAssertEqual(SpeechSettings.shared.voiceIdentifier, "kokoro:af_sky")
        XCTAssertNotNil(player.lastSwitchEvent)
        if case .voiceChanged(let previous, let current) = player.lastSwitchEvent?.kind {
            XCTAssertNil(previous)
            XCTAssertEqual(current, "kokoro:af_sky")
        } else {
            XCTFail("expected voiceChanged event")
        }
    }

    func test_setVoice_sameValue_isNoOp() {
        SpeechSettings.shared.voiceIdentifier = "kokoro:af_sky"
        player.dismissSwitchEvent()
        player.setVoice("kokoro:af_sky")
        XCTAssertNil(player.lastSwitchEvent)
    }

    func test_dismissSwitchEvent_clearsEvent() {
        player.setVoice("qwen:en_alice")
        XCTAssertNotNil(player.lastSwitchEvent)
        player.dismissSwitchEvent()
        XCTAssertNil(player.lastSwitchEvent)
    }

    // MARK: setRate

    func test_setRate_persistsToSettings() {
        let original = SpeechSettings.shared.rate
        defer { SpeechSettings.shared.rate = original }
        player.setRate(1.75)
        XCTAssertEqual(SpeechSettings.shared.rate, 1.75, accuracy: 0.001)
    }

    // MARK: load clears lastSwitchEvent

    func test_load_clearsStaleSwitchEvent() {
        player.setVoice("kokoro:other")
        XCTAssertNotNil(player.lastSwitchEvent)
        player.load([Self.sentence("Fresh.", index: 0)])
        XCTAssertNil(player.lastSwitchEvent)
    }

    // MARK: helpers

    /// Builds a `Sentence` value matching the segmenter's shape.
    /// Offsets are monotonic, lengths match the text, block 0.
    private static func sentence(_ text: String, index: Int) -> Sentence {
        let offset = index * 64
        return Sentence(
            text: text,
            blockIndex: 0,
            offsetInBlock: offset,
            lengthInBlock: (text as NSString).length
        )
    }
}
