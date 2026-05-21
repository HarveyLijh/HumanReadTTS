import Foundation
import Observation

/// Local, opt-in reading stats. Nothing leaves the device —
/// backed entirely by `UserDefaults`. Default off; user flips it
/// on from Settings → Analytics. Exists to give a personal
/// record of time spent, not to track or score the user.
///
/// We record per-sentence completion events from `SpeechPlayer`
/// with word count + duration, and keep daily roll-up counters
/// plus a streak.
@Observable
@MainActor
final class ReadingStats {
    static let shared = ReadingStats()

    // MARK: state

    var isEnabled: Bool = false {
        didSet { defaults.set(isEnabled, forKey: enabledKey) }
    }

    private(set) var totalWords: Int = 0
    private(set) var totalSeconds: Int = 0
    private(set) var todayWords: Int = 0
    private(set) var todaySeconds: Int = 0
    private(set) var currentStreak: Int = 0
    private(set) var lastActiveDay: Date = .distantPast

    // MARK: keys

    private let defaults: UserDefaults
    private let enabledKey = "app.readaloudtts.mac.stats.enabled.v1"
    private let totalWordsKey = "app.readaloudtts.mac.stats.totalWords.v1"
    private let totalSecondsKey = "app.readaloudtts.mac.stats.totalSeconds.v1"
    private let todayWordsKey = "app.readaloudtts.mac.stats.todayWords.v1"
    private let todaySecondsKey = "app.readaloudtts.mac.stats.todaySeconds.v1"
    private let streakKey = "app.readaloudtts.mac.stats.streak.v1"
    private let lastDayKey = "app.readaloudtts.mac.stats.lastDay.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: recording

    /// Called by `SpeechPlayer` after each sentence finishes.
    /// No-op when analytics are off.
    func recordSentence(wordCount: Int, duration: TimeInterval) {
        guard isEnabled, wordCount > 0, duration > 0 else { return }
        rollDayIfNeeded()
        totalWords += wordCount
        totalSeconds += Int(duration.rounded())
        todayWords += wordCount
        todaySeconds += Int(duration.rounded())
        save()
    }

    /// Call to wipe all stored stats. Preserves the `isEnabled`
    /// toggle — the user might want to reset the counters without
    /// opting out.
    func resetCounters() {
        totalWords = 0
        totalSeconds = 0
        todayWords = 0
        todaySeconds = 0
        currentStreak = 0
        lastActiveDay = .distantPast
        save()
    }

    // MARK: derived

    var wordsPerMinute: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalWords) / (Double(totalSeconds) / 60.0)
    }

    /// Today's counters are only meaningful if `lastActiveDay` is
    /// in fact today; otherwise the caller should treat them as
    /// zero until the next `recordSentence` rolls them over.
    var todayIsCurrent: Bool {
        Calendar.current.isDateInToday(lastActiveDay)
    }

    // MARK: day boundary

    /// Resets today's counters at the day boundary and updates
    /// the streak. Called before every record so that the first
    /// sentence of a new day performs the rollover.
    private func rollDayIfNeeded() {
        let calendar = Calendar.current
        if calendar.isDateInToday(lastActiveDay) {
            return
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()),
           calendar.isDate(lastActiveDay, inSameDayAs: yesterday) {
            currentStreak += 1
        } else {
            currentStreak = 1
        }
        todayWords = 0
        todaySeconds = 0
        lastActiveDay = Date()
    }

    // MARK: persistence

    private func load() {
        isEnabled = defaults.bool(forKey: enabledKey)
        totalWords = defaults.integer(forKey: totalWordsKey)
        totalSeconds = defaults.integer(forKey: totalSecondsKey)
        todayWords = defaults.integer(forKey: todayWordsKey)
        todaySeconds = defaults.integer(forKey: todaySecondsKey)
        currentStreak = defaults.integer(forKey: streakKey)
        if let stored = defaults.object(forKey: lastDayKey) as? Date {
            lastActiveDay = stored
        }
        // If the stored "today" is stale (not actually today),
        // zero out today's counters on load so the UI doesn't
        // claim the user already read this morning.
        if !Calendar.current.isDateInToday(lastActiveDay) {
            todayWords = 0
            todaySeconds = 0
        }
    }

    private func save() {
        defaults.set(totalWords, forKey: totalWordsKey)
        defaults.set(totalSeconds, forKey: totalSecondsKey)
        defaults.set(todayWords, forKey: todayWordsKey)
        defaults.set(todaySeconds, forKey: todaySecondsKey)
        defaults.set(currentStreak, forKey: streakKey)
        defaults.set(lastActiveDay, forKey: lastDayKey)
    }
}

// MARK: helpers

extension String {
    /// Rough word count — whitespace-separated tokens after
    /// collapsing consecutive whitespace. Good enough for
    /// `ReadingStats` which wants relative magnitude, not a
    /// precise linguistic word count.
    var roughWordCount: Int {
        split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}
