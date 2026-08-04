import XCTest
@testable import HumanReadTTS

@MainActor
final class ReadingStatsTests: XCTestCase {

    private func freshStats() -> (ReadingStats, UserDefaults, String) {
        let suite = "app.humanreadtts.mac.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (ReadingStats(defaults: defaults), defaults, suite)
    }

    override func tearDown() async throws {
        // Each test cleans its own suite; nothing to do here.
        try await super.tearDown()
    }

    // MARK: gating

    func test_whenDisabled_recordSentenceIsNoOp() {
        let (stats, defaults, suite) = freshStats()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(stats.isEnabled)
        stats.recordSentence(wordCount: 10, duration: 5)

        XCTAssertEqual(stats.totalWords, 0)
        XCTAssertEqual(stats.totalSeconds, 0)
    }

    func test_whenEnabled_accumulates() {
        let (stats, defaults, suite) = freshStats()
        defer { defaults.removePersistentDomain(forName: suite) }
        stats.isEnabled = true

        stats.recordSentence(wordCount: 10, duration: 5)
        stats.recordSentence(wordCount: 20, duration: 10)

        XCTAssertEqual(stats.totalWords, 30)
        XCTAssertEqual(stats.totalSeconds, 15)
        XCTAssertEqual(stats.todayWords, 30)
        XCTAssertEqual(stats.todaySeconds, 15)
    }

    // MARK: derived

    func test_wordsPerMinute_isTotalWordsOverTotalMinutes() {
        let (stats, defaults, suite) = freshStats()
        defer { defaults.removePersistentDomain(forName: suite) }
        stats.isEnabled = true

        stats.recordSentence(wordCount: 200, duration: 60)
        XCTAssertEqual(stats.wordsPerMinute, 200, accuracy: 0.5)
    }

    func test_wordsPerMinute_withNoRecords_isZero() {
        let (stats, defaults, suite) = freshStats()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(stats.wordsPerMinute, 0)
    }

    // MARK: input validation

    func test_zeroWordCount_doesNotAccumulate() {
        let (stats, defaults, suite) = freshStats()
        defer { defaults.removePersistentDomain(forName: suite) }
        stats.isEnabled = true

        stats.recordSentence(wordCount: 0, duration: 10)
        stats.recordSentence(wordCount: 5, duration: 0)

        XCTAssertEqual(stats.totalWords, 0)
        XCTAssertEqual(stats.totalSeconds, 0)
    }

    // MARK: persistence

    func test_persistsAcrossInstances() {
        let suite = "app.humanreadtts.mac.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = ReadingStats(defaults: defaults)
        first.isEnabled = true
        first.recordSentence(wordCount: 50, duration: 30)

        let second = ReadingStats(defaults: defaults)
        XCTAssertTrue(second.isEnabled)
        XCTAssertEqual(second.totalWords, 50)
        XCTAssertEqual(second.totalSeconds, 30)
    }

    // MARK: reset

    func test_resetCounters_preservesIsEnabledToggle() {
        let (stats, defaults, suite) = freshStats()
        defer { defaults.removePersistentDomain(forName: suite) }
        stats.isEnabled = true
        stats.recordSentence(wordCount: 42, duration: 60)

        stats.resetCounters()

        XCTAssertTrue(stats.isEnabled)
        XCTAssertEqual(stats.totalWords, 0)
        XCTAssertEqual(stats.totalSeconds, 0)
        XCTAssertEqual(stats.currentStreak, 0)
    }

    // MARK: rough word count

    func test_roughWordCount() {
        XCTAssertEqual("hello world".roughWordCount, 2)
        XCTAssertEqual("one   two\tthree\nfour".roughWordCount, 4)
        XCTAssertEqual("".roughWordCount, 0)
        XCTAssertEqual("   ".roughWordCount, 0)
    }
}
