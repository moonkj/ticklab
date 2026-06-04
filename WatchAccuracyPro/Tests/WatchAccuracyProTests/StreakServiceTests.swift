import XCTest
@testable import WatchAccuracyPro

/// StreakService 순수 헬퍼 검증 — UTC 고정 캘린더로 타임존 비결정성 제거.
final class StreakServiceTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// "2026-06-04" 형태 문자열을 UTC 정오 Date 로.
    private func day(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = TimeZone(identifier: "UTC")!
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s + " 12:00")!
    }

    func test_empty_is_zero() {
        let r = StreakService.streak(from: [], now: day("2026-06-04"), calendar: calendar)
        XCTAssertEqual(r, .zero)
    }

    func test_current_streak_ending_today() {
        let now = day("2026-06-04")
        let ts = [day("2026-06-02"), day("2026-06-03"), day("2026-06-04")]
        let r = StreakService.streak(from: ts, now: now, calendar: calendar)
        XCTAssertEqual(r.current, 3)
        XCTAssertEqual(r.longest, 3)
    }

    func test_current_streak_alive_when_ending_yesterday() {
        let now = day("2026-06-04")
        let ts = [day("2026-06-02"), day("2026-06-03")]   // 어제까지
        let r = StreakService.streak(from: ts, now: now, calendar: calendar)
        XCTAssertEqual(r.current, 2)
    }

    func test_current_streak_broken_when_gap_over_one_day() {
        let now = day("2026-06-04")
        let ts = [day("2026-06-01"), day("2026-06-02")]   // 그제 이전에 끊김
        let r = StreakService.streak(from: ts, now: now, calendar: calendar)
        XCTAssertEqual(r.current, 0)
        XCTAssertEqual(r.longest, 2)
    }

    func test_duplicate_same_day_counts_once() {
        let now = day("2026-06-04")
        let ts = [day("2026-06-04"), day("2026-06-04"), day("2026-06-03")]
        let r = StreakService.streak(from: ts, now: now, calendar: calendar)
        XCTAssertEqual(r.current, 2)
        XCTAssertEqual(r.longest, 2)
    }

    func test_longest_distinct_from_current() {
        let now = day("2026-06-20")
        // 과거 5일 연속(longest) + 최근 오늘만 1일(current=1).
        let ts = [
            day("2026-06-01"), day("2026-06-02"), day("2026-06-03"),
            day("2026-06-04"), day("2026-06-05"),
            day("2026-06-20")
        ]
        let r = StreakService.streak(from: ts, now: now, calendar: calendar)
        XCTAssertEqual(r.current, 1)
        XCTAssertEqual(r.longest, 5)
    }
}
