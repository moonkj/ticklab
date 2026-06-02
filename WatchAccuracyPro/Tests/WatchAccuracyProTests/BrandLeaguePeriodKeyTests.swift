import XCTest
@testable import WatchAccuracyPro

/// `SupabaseBrandLeagueService.periodKey(type:date:)` 순수 문자열 포맷 회귀 보호.
/// 네트워크/시스템 시각 의존 없음 — 고정 Date 를 주입해 결정론적.
///
/// 주의: `periodKey` 내부는 Calendar(gregorian) + locale(en_US_POSIX) 을 명시하지만
/// timeZone 은 설정하지 않는다 → Calendar 기본값인 TimeZone.current 를 사용.
/// 픽스처 Date 를 만들 때도 동일한 TimeZone.current 를 사용해 기기 시간대 무관하게
/// 예상 컴포넌트(year/month/day)가 일치하도록 한다.
@MainActor
final class BrandLeaguePeriodKeyTests: XCTestCase {

    // MARK: - 픽스처

    /// 테스트용 고정 달력: 함수가 사용하는 캘린더와 동일한 timezone 을 공유.
    /// (locale 차이는 year/month/day 숫자 자체에 영향 없음)
    private var fixedCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        // timeZone 미설정 → Calendar 기본값 = TimeZone.current → periodKey 와 동일 해석
        return cal
    }

    /// 2024-03-13 12:00 (기기 현지 시간) — 기기 시간대가 어느 쪽이든
    /// 현지 날짜/시각 컴포넌트가 모두 2024-03-13 으로 일치한다.
    private var fixedDate: Date {
        var dc = DateComponents()
        dc.year = 2024; dc.month = 3; dc.day = 13
        dc.hour = 12; dc.minute = 0; dc.second = 0
        return fixedCalendar.date(from: dc)!
    }

    // MARK: - day 포맷

    func test_dayKey_format_is_yyyy_mm_dd() {
        let key = SupabaseBrandLeagueService.periodKey(type: "day", date: fixedDate)
        XCTAssertEqual(key, "2024-03-13")
    }

    func test_dayKey_zero_pads_single_digit_month_and_day() {
        // 2025-01-05 → "2025-01-05" (zero-pad 검증)
        var dc = DateComponents()
        dc.year = 2025; dc.month = 1; dc.day = 5
        dc.hour = 12; dc.minute = 0; dc.second = 0
        let date = fixedCalendar.date(from: dc)!
        let key = SupabaseBrandLeagueService.periodKey(type: "day", date: date)
        XCTAssertEqual(key, "2025-01-05")
    }

    // MARK: - week 포맷

    func test_weekKey_format_structure() {
        let key = SupabaseBrandLeagueService.periodKey(type: "week", date: fixedDate)
        // 형식: "YYYY-Www" — 연도 하이픈 W 두자리
        // 정확한 주차값은 TimeZone 의존 없음 (calendar.yearForWeekOfYear / weekOfYear)
        let parts = key.split(separator: "-")
        XCTAssertEqual(parts.count, 2, "week 키 구분자 하나 기대, got: \(key)")
        XCTAssertEqual(parts[0], "2024", "연도 부분이 2024 이어야 함, got: \(key)")
        XCTAssertTrue(parts[1].hasPrefix("W"), "주차 부분 W 로 시작 필요, got: \(key)")
        let weekNum = parts[1].dropFirst()
        XCTAssertEqual(weekNum.count, 2, "주차 두 자리 zero-pad 필요, got: \(weekNum)")
        XCTAssertNotNil(Int(weekNum), "주차는 숫자여야 함, got: \(weekNum)")
        if let wn = Int(weekNum) {
            XCTAssertTrue((1...53).contains(wn), "유효한 주차 범위(1-53) 이어야 함, got: \(wn)")
        }
    }

    func test_weekKey_zero_pads_single_digit_week() {
        // 연초 1주차 — zero-pad 검증
        var dc = DateComponents()
        dc.year = 2024; dc.month = 1; dc.day = 3  // 2024-01-03 은 대부분 시간대에서 W01
        dc.hour = 12; dc.minute = 0; dc.second = 0
        let date = fixedCalendar.date(from: dc)!
        let key = SupabaseBrandLeagueService.periodKey(type: "week", date: date)
        XCTAssertTrue(key.contains("W0"), "1자리 주차는 W0x zero-pad 해야 함, got: \(key)")
    }

    func test_weekKey_contains_year() {
        let key = SupabaseBrandLeagueService.periodKey(type: "week", date: fixedDate)
        XCTAssertTrue(key.contains("2024"), "week 키에 연도 2024 포함돼야 함, got: \(key)")
    }

    // MARK: - month 포맷

    func test_monthKey_format_is_yyyy_mm() {
        let key = SupabaseBrandLeagueService.periodKey(type: "month", date: fixedDate)
        XCTAssertEqual(key, "2024-03")
    }

    func test_monthKey_zero_pads_single_digit_month() {
        var dc = DateComponents()
        dc.year = 2025; dc.month = 6; dc.day = 15
        dc.hour = 12; dc.minute = 0; dc.second = 0
        let date = fixedCalendar.date(from: dc)!
        let key = SupabaseBrandLeagueService.periodKey(type: "month", date: date)
        XCTAssertEqual(key, "2025-06")
    }

    func test_monthKey_starts_with_year_hyphen() {
        let key = SupabaseBrandLeagueService.periodKey(type: "month", date: fixedDate)
        XCTAssertTrue(key.hasPrefix("2024-"), "month 키는 연도 우선, got: \(key)")
    }

    // MARK: - year 포맷

    func test_yearKey_is_four_digit_year() {
        let key = SupabaseBrandLeagueService.periodKey(type: "year", date: fixedDate)
        XCTAssertEqual(key, "2024")
    }

    func test_yearKey_changes_across_calendar_years() {
        var dc2023 = DateComponents()
        dc2023.year = 2023; dc2023.month = 6; dc2023.day = 15
        dc2023.hour = 12; dc2023.minute = 0; dc2023.second = 0
        let date2023 = fixedCalendar.date(from: dc2023)!

        var dc2025 = DateComponents()
        dc2025.year = 2025; dc2025.month = 6; dc2025.day = 15
        dc2025.hour = 12; dc2025.minute = 0; dc2025.second = 0
        let date2025 = fixedCalendar.date(from: dc2025)!

        XCTAssertEqual(SupabaseBrandLeagueService.periodKey(type: "year", date: date2023), "2023")
        XCTAssertEqual(SupabaseBrandLeagueService.periodKey(type: "year", date: date2025), "2025")
    }

    // MARK: - 타입별 키가 같은 날짜에서 서로 달라야 한다

    func test_different_types_produce_different_keys() {
        // day/week/month/year 는 구조적으로 서로 다른 포맷이므로 항상 달라야 한다.
        // (day 에는 하이픈이 2개, week 에는 W, month 에는 하이픈 1개, year 에는 하이픈 없음)
        let day   = SupabaseBrandLeagueService.periodKey(type: "day",   date: fixedDate)
        let week  = SupabaseBrandLeagueService.periodKey(type: "week",  date: fixedDate)
        let month = SupabaseBrandLeagueService.periodKey(type: "month", date: fixedDate)
        let year  = SupabaseBrandLeagueService.periodKey(type: "year",  date: fixedDate)

        let all = [day, week, month, year]
        XCTAssertEqual(Set(all).count, all.count, "day/week/month/year 키 중복: \(all)")
    }

    // MARK: - 결정론적 안정성 (같은 입력 → 같은 출력)

    func test_stability_same_input_same_output() {
        for type in ["day", "week", "month", "year"] {
            let first  = SupabaseBrandLeagueService.periodKey(type: type, date: fixedDate)
            let second = SupabaseBrandLeagueService.periodKey(type: type, date: fixedDate)
            XCTAssertEqual(first, second, "\(type) 키가 동일 입력에서 달라짐 — 비결정론 버그")
        }
    }

    // MARK: - unknown type → empty string

    func test_unknown_type_returns_empty_string() {
        XCTAssertEqual(SupabaseBrandLeagueService.periodKey(type: "quarter", date: fixedDate), "")
        XCTAssertEqual(SupabaseBrandLeagueService.periodKey(type: "",        date: fixedDate), "")
    }

    // MARK: - 모든 타입이 4자리 연도를 포함한다

    func test_all_types_contain_four_digit_year_string() {
        for type in ["day", "week", "month", "year"] {
            let key = SupabaseBrandLeagueService.periodKey(type: type, date: fixedDate)
            XCTAssertTrue(key.contains("2024"),
                          "\(type) 키에 4자리 연도 '2024' 없음: \(key)")
        }
    }

    // MARK: - 12월 31일 경계: year/month/day 모두 정확

    func test_december_31_all_types_correct() {
        var dc = DateComponents()
        dc.year = 2024; dc.month = 12; dc.day = 31
        dc.hour = 12; dc.minute = 0; dc.second = 0
        let date = fixedCalendar.date(from: dc)!

        XCTAssertEqual(SupabaseBrandLeagueService.periodKey(type: "year",  date: date), "2024")
        XCTAssertEqual(SupabaseBrandLeagueService.periodKey(type: "month", date: date), "2024-12")
        XCTAssertEqual(SupabaseBrandLeagueService.periodKey(type: "day",   date: date), "2024-12-31")
    }

    // MARK: - day 타입이 month 타입 결과를 접두어로 포함하는 구조 불변식

    func test_dayKey_starts_with_monthKey() {
        let dayKey   = SupabaseBrandLeagueService.periodKey(type: "day",   date: fixedDate)
        let monthKey = SupabaseBrandLeagueService.periodKey(type: "month", date: fixedDate)
        XCTAssertTrue(dayKey.hasPrefix(monthKey),
                      "day 키('\(dayKey)') 는 month 키('\(monthKey)') 로 시작해야 함 — 포맷 정합")
    }

    // MARK: - month 타입이 year 타입 결과를 접두어로 포함하는 구조 불변식

    func test_monthKey_starts_with_yearKey() {
        let monthKey = SupabaseBrandLeagueService.periodKey(type: "month", date: fixedDate)
        let yearKey  = SupabaseBrandLeagueService.periodKey(type: "year",  date: fixedDate)
        XCTAssertTrue(monthKey.hasPrefix(yearKey),
                      "month 키('\(monthKey)') 는 year 키('\(yearKey)') 로 시작해야 함 — 포맷 정합")
    }
}
