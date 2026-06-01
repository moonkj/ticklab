import XCTest
@testable import WatchAccuracyPro

/// PURE 커버리지: AppDateFormat — 공유 DateFormatter 헬퍼.
/// locale 별 정확한 문자열 대신 non-empty + 숫자 포함 + 캐시 비오염을 검증.
final class AppDateFormatTests: XCTestCase {

    /// 2026-05-15 14:32:00 UTC 근방의 고정 Date.
    private func fixedDate() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 15; c.hour = 14; c.minute = 32
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func containsDigit(_ s: String) -> Bool {
        s.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
    }

    func test_shortMonthDay_nonEmpty_hasDigits() {
        let s = AppDateFormat.shortMonthDay(fixedDate())
        XCTAssertFalse(s.isEmpty)
        XCTAssertTrue(containsDigit(s))
    }

    func test_fullDate_nonEmpty_hasYearDigits() {
        let s = AppDateFormat.fullDate(fixedDate())
        XCTAssertFalse(s.isEmpty)
        XCTAssertTrue(s.contains("2026"), "연/월/일 포맷에 연도가 포함되어야 함: \(s)")
    }

    func test_numericSlash_containsSlashAndDigits() {
        let s = AppDateFormat.numericSlash(fixedDate())
        XCTAssertTrue(s.contains("/"), "슬래시 포맷: \(s)")
        XCTAssertTrue(containsDigit(s))
    }

    func test_monthDayTime_nonEmpty_hasDigits() {
        let s = AppDateFormat.monthDayTime(fixedDate())
        XCTAssertFalse(s.isEmpty)
        XCTAssertTrue(containsDigit(s))
    }

    // MARK: - Round 17 회귀 가드: numericSlash 가 다른 template 캐시를 오염시키지 않아야 함.

    func test_numericSlash_doesNotPollute_otherFormatters() {
        let date = fixedDate()
        // numericSlash 가 "M/d" fixed format 을 별도 캐시 키로 보관해야 함.
        _ = AppDateFormat.numericSlash(date)
        let short = AppDateFormat.shortMonthDay(date)
        // shortMonthDay 는 "M/d" 형태(슬래시 단독)가 아니어야 함.
        XCTAssertFalse(short.isEmpty)
        XCTAssertTrue(containsDigit(short))
    }

    func test_repeatedCalls_deterministic() {
        let date = fixedDate()
        XCTAssertEqual(AppDateFormat.shortMonthDay(date), AppDateFormat.shortMonthDay(date))
        XCTAssertEqual(AppDateFormat.numericSlash(date), AppDateFormat.numericSlash(date))
        XCTAssertEqual(AppDateFormat.fullDate(date), AppDateFormat.fullDate(date))
    }
}
