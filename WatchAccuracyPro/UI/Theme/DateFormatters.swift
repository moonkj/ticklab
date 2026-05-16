import Foundation

/// 앱 전체 날짜 포맷 통일 — Korean locale 에서 ".dateTime.month().day()" 가
/// "5월 15" 로 출력되는 문제 회피. 모든 날짜 표시는 이 헬퍼 사용.
enum AppDateFormat {
    /// "5월 15일" / "May 15" — 월/일 (현재 연도).
    static func shortMonthDay(_ date: Date) -> String {
        Self.cachedFormatter(template: "MMMd").string(from: date)
    }

    /// "2026년 5월 15일" / "May 15, 2026" — 연/월/일.
    static func fullDate(_ date: Date) -> String {
        Self.cachedFormatter(template: "yMMMd").string(from: date)
    }

    /// "5/15" — 간결한 슬래시 포맷 (그래프 axis 등).
    /// Round 17 (Hyemi): 이전 구현이 cachedFormatter("Md") 의 dateFormat 를 매 호출 mutate 하던 버그.
    ///   다음 "Md" 요청자에게 "M/d" 가 오염된 상태로 반환됨. 별도 캐시 키로 분리.
    static func numericSlash(_ date: Date) -> String {
        Self.cachedFormatter(key: "slash:M/d", configure: { $0.dateFormat = "M/d" }).string(from: date)
    }

    /// "5월 15일 14:32" / "May 15, 2:32 PM" — 월/일 + 시각.
    static func monthDayTime(_ date: Date) -> String {
        Self.cachedFormatter(template: "MMMdHm").string(from: date)
    }

    // MARK: - Cache (DateFormatter 생성 비용)

    private static var formatters: [String: DateFormatter] = [:]
    private static let lock = NSLock()

    private static func cachedFormatter(template: String) -> DateFormatter {
        lock.lock(); defer { lock.unlock() }
        if let cached = formatters[template] { return cached }
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate(template)
        formatters[template] = f
        return f
    }

    /// Round 17: configure 클로저로 fixed-format 캐시 분리. key 가 별도라 template-based 캐시와 충돌 X.
    private static func cachedFormatter(key: String, configure: (DateFormatter) -> Void) -> DateFormatter {
        lock.lock(); defer { lock.unlock() }
        if let cached = formatters[key] { return cached }
        let f = DateFormatter()
        f.locale = Locale.current
        configure(f)
        formatters[key] = f
        return f
    }
}
