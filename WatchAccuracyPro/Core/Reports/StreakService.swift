import Foundation
import SwiftData

/// 측정 streak(연속 측정일) 계산 — 리텐션 표면화용.
/// 순수 계산 헬퍼([Date] 입력)와 SwiftData 진입점(ModelContext)을 분리해 테스트 가능하게 둔다.
///
/// "streak" 정의: 측정이 1건이라도 있는 distinct 날짜(startOfDay)가 하루 간격으로 끊김 없이
/// 이어진 길이. current streak 은 "오늘 또는 어제"로 끝나는 run 만 살아있는 것으로 본다
/// (오늘 아직 측정 안 했어도 어제까지 이어졌으면 streak 유지, 그제까지면 0).
enum StreakService {

    /// streak 계산 결과.
    struct StreakResult: Equatable {
        /// 현재 살아있는 연속 측정일. 오늘/어제로 끝나지 않으면 0.
        let current: Int
        /// 기록상 가장 길었던 연속 측정일.
        let longest: Int

        static let zero = StreakResult(current: 0, longest: 0)
    }

    // MARK: - Pure helpers ([Date] 입력 — 테스트 가능)

    /// 측정 timestamp 목록에서 current/longest streak 을 계산한다.
    /// - Parameters:
    ///   - timestamps: 측정 시각(중복·미정렬 허용).
    ///   - now: "오늘" 기준 시각. 기본 현재.
    ///   - calendar: 날짜 경계 계산용. 기본 현재 캘린더.
    static func streak(from timestamps: [Date],
                       now: Date = Date(),
                       calendar: Calendar = .current) -> StreakResult {
        guard !timestamps.isEmpty else { return .zero }

        // distinct 측정일(startOfDay) 오름차순.
        let days = Set(timestamps.map { calendar.startOfDay(for: $0) }).sorted()

        let longest = longestRun(sortedDays: days, calendar: calendar)
        let current = currentRun(sortedDays: days, now: now, calendar: calendar)
        return StreakResult(current: current, longest: longest)
    }

    /// 정렬된 distinct 측정일에서 가장 긴 연속 run 길이.
    private static func longestRun(sortedDays: [Date], calendar: Calendar) -> Int {
        guard !sortedDays.isEmpty else { return 0 }
        var longest = 1
        var run = 1
        for i in 1..<sortedDays.count {
            let gap = calendar.dateComponents([.day], from: sortedDays[i - 1], to: sortedDays[i]).day ?? 0
            if gap == 1 {
                run += 1
                longest = max(longest, run)
            } else {
                run = 1   // gap==0 은 distinct set 이라 발생하지 않음.
            }
        }
        return longest
    }

    /// 오늘 또는 어제로 끝나는 살아있는 run 길이. 그 외엔 0.
    private static func currentRun(sortedDays: [Date], now: Date, calendar: Calendar) -> Int {
        guard let last = sortedDays.last else { return 0 }
        let today = calendar.startOfDay(for: now)
        let lastToToday = calendar.dateComponents([.day], from: last, to: today).day ?? Int.max
        // 마지막 측정일이 오늘(0)도 어제(1)도 아니면 끊긴 것.
        guard lastToToday == 0 || lastToToday == 1 else { return 0 }

        var run = 1
        var idx = sortedDays.count - 1
        while idx > 0 {
            let gap = calendar.dateComponents([.day], from: sortedDays[idx - 1], to: sortedDays[idx]).day ?? 0
            if gap == 1 {
                run += 1
                idx -= 1
            } else {
                break
            }
        }
        return run
    }

    // MARK: - SwiftData 진입점

    /// 모든 측정의 timestamp 를 읽어 streak 계산. (집계만 — @Model 쓰기 없음.)
    @MainActor
    static func currentStreak(in context: ModelContext,
                              now: Date = Date(),
                              calendar: Calendar = .current) -> StreakResult {
        let desc = FetchDescriptor<WatchMeasurement>()
        let measurements = (try? context.fetch(desc)) ?? []
        return streak(from: measurements.map(\.timestamp), now: now, calendar: calendar)
    }
}
