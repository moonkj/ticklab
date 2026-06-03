import Foundation
import SwiftData
import WidgetKit

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
        // 감사 수정: 모든 wear 토글 경로(앱/위젯 reconcile)가 위젯 "오늘 착용" 상태를 갱신 + reload.
        defer { syncWidgetWornStatus(in: context) }
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

    /// Sprint 1 (P2-12 ROI): 단일 시계의 누적 착용 일수. 없으면 0.
    static func wearCount(for watch: Watch, in context: ModelContext) -> Int {
        let watchID = watch.id
        let predicate = #Predicate<WearLog> { $0.watch?.id == watchID }
        let descriptor = FetchDescriptor<WearLog>(predicate: predicate)
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// 위젯 "오늘 착용" 상태 동기화 — 최근 측정 시계의 오늘 착용 여부를 App Group 에 권위값으로 쓰고
    ///   위젯 timeline reload. 모든 wear 변경(앱 토글·측정·위젯 reconcile) 후 호출돼 위젯이
    ///   pending 큐가 아닌 **실제 상태**를 반영하게 한다(앱에서 해제 시 위젯도 즉시 풀림).
    static func syncWidgetWornStatus(in context: ModelContext) {
        let descriptor = FetchDescriptor<WatchMeasurement>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        let worn: Bool = {
            guard let latest = (try? context.fetch(descriptor))?.first, let watch = latest.watch else { return false }
            return isWornToday(watch, in: context)
        }()
        SharedSnapshotStore.writeWornToday(worn)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Sprint 2 (P1-1) → 감사 수정: 위젯 AppIntent 가 큐잉한 desired 상태로 reconcile.
    /// 위젯은 탭 시 worn 을 낙관적으로 flip 해 두므로, 앱은 그 desired 값에 실제 WearLog 를 맞춘다
    ///   (blind toggle 아닌 set — 다중 탭/앱내 변경과 일관, 누른 채 남는 버그 방지).
    /// 메인 앱 launch / scenePhase=.active 시 호출.
    static func consumePendingWearToggle(in context: ModelContext) {
        let defaults = SharedSnapshotStore.defaults
        guard let pending = defaults?.object(forKey: SharedSnapshotStore.pendingWearToggleKey) as? Double, pending > 0 else { return }
        defaults?.removeObject(forKey: SharedSnapshotStore.pendingWearToggleKey)
        let descriptor = FetchDescriptor<WatchMeasurement>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        guard let latestMeasurement = (try? context.fetch(descriptor))?.first,
              let watch = latestMeasurement.watch else {
            syncWidgetWornStatus(in: context); return
        }
        let desired = SharedSnapshotStore.readWornToday()
        if isWornToday(watch, in: context) != desired {
            _ = toggleToday(watch, in: context, auto: false)   // 내부 defer 에서 syncWidgetWornStatus 호출
        } else {
            syncWidgetWornStatus(in: context)                  // 이미 일치 — 권위값/위젯만 정합
        }
    }

}
