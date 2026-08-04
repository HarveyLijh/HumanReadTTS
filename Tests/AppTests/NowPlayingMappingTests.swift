import XCTest
import MediaPlayer
@testable import HumanReadTTS

@MainActor
final class NowPlayingMappingTests: XCTestCase {

    private func sentence(_ text: String) -> Sentence {
        Sentence(text: text, blockIndex: 0, offsetInBlock: 0, lengthInBlock: text.count)
    }

    func test_infoDictionary_mapsAllKeys() {
        let meta = NowPlayingMetadata(
            title: "Hello there", albumTitle: "HumanReadTTS",
            elapsed: 12, duration: 60, isPlaying: true
        )
        let info = NowPlayingController.makeInfoDictionary(meta)
        XCTAssertEqual(info[MPMediaItemPropertyTitle] as? String, "Hello there")
        XCTAssertEqual(info[MPMediaItemPropertyAlbumTitle] as? String, "HumanReadTTS")
        XCTAssertEqual(info[MPMediaItemPropertyPlaybackDuration] as? Double, 60)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 12)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 1.0,
                       "positions are already wall-clock seconds, so the clock advances at 1x")
    }

    func test_pausedReportsZeroRate_soSystemClockFreezes() {
        let meta = NowPlayingMetadata(
            title: "x", albumTitle: "y", elapsed: 5, duration: 10, isPlaying: false
        )
        let info = NowPlayingController.makeInfoDictionary(meta)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0.0,
                       "paused must report rate 0 so the elapsed clock freezes")
    }

    func test_title_usesCurrentSentenceTrimmedAndTruncated() {
        let sentences = [sentence("  First sentence.  "), sentence("Second.")]
        XCTAssertEqual(NowPlayingController.title(for: sentences, index: 0), "First sentence.")

        let long = String(repeating: "ab ", count: 50) // > 64 chars
        let truncated = NowPlayingController.title(for: [sentence(long)], index: 0)
        XCTAssertTrue(truncated.hasSuffix("…"))
        XCTAssertLessThanOrEqual(truncated.count, 66)
    }

    func test_title_fallsBackToAppNameWhenOutOfRangeOrEmpty() {
        XCTAssertEqual(NowPlayingController.title(for: [], index: 0), "HumanReadTTS")
        XCTAssertEqual(NowPlayingController.title(for: [sentence("   ")], index: 0), "HumanReadTTS")
    }

    func test_remoteCommands_disabledWhenNothingLoaded() {
        for kind in [RemoteCommandKind.togglePlayPause, .play, .pause, .next, .previous, .stop] {
            XCTAssertFalse(NowPlayingController.isEnabled(kind, sentenceCount: 0),
                           "\(kind) must be disabled with no sentences")
            XCTAssertTrue(NowPlayingController.isEnabled(kind, sentenceCount: 3))
        }
    }
}
