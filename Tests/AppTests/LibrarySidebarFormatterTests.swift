import XCTest
@testable import ReadAloudTTS

/// `LibrarySidebarView.formatted` replaces the auto-ticking
/// relative-date `Text`. These tests pin the rules for the
/// "today / yesterday / this week / older" buckets so the fix
/// doesn't silently regress.
@MainActor
final class LibrarySidebarFormatterTests: XCTestCase {

    func test_today_returnsTodayPrefixWithTime() {
        let now = Date()
        let result = LibrarySidebarView.formatted(now, relativeTo: now)
        XCTAssertTrue(result.hasPrefix("Today "), "got \(result)")
    }

    func test_yesterday_returnsYesterday() {
        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        XCTAssertEqual(
            LibrarySidebarView.formatted(yesterday, relativeTo: now),
            "Yesterday"
        )
    }

    func test_older_returnsMonthDay() {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 15
        let now = Calendar.current.date(from: components)!
        var prev = DateComponents()
        prev.year = 2025
        prev.month = 11
        prev.day = 3
        let old = Calendar.current.date(from: prev)!
        let result = LibrarySidebarView.formatted(old, relativeTo: now)
        // Locale-dependent ordering, but "Nov" and "3" must both appear.
        XCTAssertTrue(result.contains("Nov"), "got \(result)")
        XCTAssertTrue(result.contains("3"), "got \(result)")
    }
}
