import Foundation
import SwiftData

/// 착용 로그 비즈니스 로직 — 오늘 기록 / 일자별 카운트 / 시계별 누적.
/// Pivot Addendum 의 "Journey" axis — 데일리 시계 일상 track.
@MainActor
enum WearLogService {
    /// 오늘 (day-granularity) 해당 시계 착용 기록 toggle. 이미 있으면 삭제, 없으면 추가.
    /// - Returns: 액션 결과 — true 면 추가됨, false 면 삭제됨.
    @discardableResult
    static func toggleToday(_ watch: Watch, in context: ModelContext, auto: Bool = false) -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let watchId = watch.id
        let descriptor = FetchDescriptor<WearLog>(predicate: #Predicate { log in
            log.watch?.id == watchId && log.date == today
        })
        // Round 168: mood 캐시 무효화 — wear 변경 시 즉시 반영.
        defer { WatchMoodService.invalidate(for: watch) }
        if let existing = (try? context.fetch(descriptor))?.first {
            context.delete(existing)
            try? context.save()
            SupabaseBrandLeagueService.shared.syncAfterWearToggle(watch: watch, context: context)
            return false
        }
        let log = WearLog(watch: watch, date: today, isAuto: auto)
        context.insert(log)
        try? context.save()
        SupabaseBrandLeagueService.shared.syncAfterWearToggle(watch: watch, context: context)
        return true
    }

    /// 측정 시 자동 호출 — 오늘 이 시계 wear log 가 없으면 생성 (isAuto=true).
    static func ensureTodayWearOnMeasure(_ watch: Watch, in context: ModelContext) {
        let today = Calendar.current.startOfDay(for: Date())
        let watchId = watch.id
        let descriptor = FetchDescriptor<WearLog>(predicate: #Predicate { log in
            log.watch?.id == watchId && log.date == today
        })
        if (try? context.fetch(descriptor))?.first == nil {
            let log = WearLog(watch: watch, date: today, isAuto: true)
            context.insert(log)
            try? context.save()
            WatchMoodService.invalidate(for: watch)
        }
    }

    /// 오늘 wear log 가 있는지.
    static func isWornToday(_ watch: Watch, in context: ModelContext) -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let watchId = watch.id
        let descriptor = FetchDescriptor<WearLog>(predicate: #Predicate { log in
            log.watch?.id == watchId && log.date == today
        })
        return ((try? context.fetch(descriptor))?.first) != nil
    }

    /// 지난 N일 (오늘 포함) 의 일자별 착용 카운트.
    /// - Returns: 일자(=startOfDay) → 그 날 착용한 시계 수.
    static func dailyCounts(days: Int, in context: ModelContext) -> [(date: Date, count: Int)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        let descriptor = FetchDescriptor<WearLog>(predicate: #Predicate { log in
            log.date >= start
        })
        let logs = (try? context.fetch(descriptor)) ?? []
        let grouped = Dictionary(grouping: logs, by: { $0.date })
        var result: [(date: Date, count: Int)] = []
        for i in 0..<days {
            if let d = cal.date(byAdding: .day, value: i, to: start) {
                result.append((date: d, count: grouped[d]?.count ?? 0))
            }
        }
        return result
    }

    /// 시계별 누적 착용 일수 (전체 기간).
    static func cumulativeByWatch(in context: ModelContext) -> [(watch: Watch, days: Int)] {
        let descriptor = FetchDescriptor<WearLog>()
        let logs = (try? context.fetch(descriptor)) ?? []
        let grouped = Dictionary(grouping: logs.compactMap { $0.watch.map { ($0, $0.id) } }, by: { $0.1 })
        return grouped.compactMap { _, items in
            guard let watch = items.first?.0 else { return nil }
            return (watch: watch, days: items.count)
        }
        .sorted { $0.days > $1.days }
    }

}
