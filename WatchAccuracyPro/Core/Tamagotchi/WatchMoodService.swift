import Foundation
import SwiftData

/// 시계 다마고치 — 보관함 시계를 디지털 생명체처럼 다룬다.
/// 마지막 착용 / 마지막 감기 / 마지막 측정 활동을 종합하여 에너지·기분 상태를 산출.
@MainActor
enum WatchMoodService {

    enum Mood: String, CaseIterable {
        case energetic     // 0–24h 내 착용·측정
        case happy         // 24–72h
        case sleepy        // 72h–7d
        case dormant       // 7d+ 미접촉
        case lowBattery    // quartz, 배터리 임박
        case needsWind     // manual, 24h+ 미감기

        var emoji: String {
            switch self {
            case .energetic:  return "😄"
            case .happy:      return "🙂"
            case .sleepy:     return "😪"
            case .dormant:    return "💤"
            case .lowBattery: return "🪫"
            case .needsWind:  return "🌀"
            }
        }

        var label: String {
            switch self {
            case .energetic:  return String(localized: "mood.label.energetic")
            case .happy:      return String(localized: "mood.label.happy")
            case .sleepy:     return String(localized: "mood.label.sleepy")
            case .dormant:    return String(localized: "mood.label.dormant")
            case .lowBattery: return String(localized: "mood.label.lowBattery")
            case .needsWind:  return String(localized: "mood.label.needsWind")
            }
        }

        /// 0..100. UI 게이지.
        var energy: Int {
            switch self {
            case .energetic:  return 100
            case .happy:      return 70
            case .sleepy:     return 40
            case .dormant:    return 10
            case .lowBattery: return 15
            case .needsWind:  return 25
            }
        }
    }

    struct Status {
        let mood: Mood
        let lastInteraction: Date?
        let daysSinceInteraction: Int?
    }

    /// Round 168: hour 단위 캐시 — Collection scroll 시 fetch 폭주 방지.
    private struct CacheEntry {
        let status: Status
        let cachedAt: Date
    }
    private static var cache: [UUID: CacheEntry] = [:]
    private static let cacheTTL: TimeInterval = 60 * 30  // 30분

    /// 시계의 현재 상태 계산. 우선순위:
    /// 1) Quartz + 배터리 만기 7일 이내 → .lowBattery
    /// 2) Manual + 24h+ 미감기 (= 24h+ 미착용) → .needsWind
    /// 3) 마지막 활동 시각 기반 energetic / happy / sleepy / dormant.
    /// Round 168: 30분 캐시 (mood 는 hour 단위로만 변함).
    static func status(of watch: Watch, in context: ModelContext) -> Status {
        let now = Date()
        if let entry = cache[watch.id],
           now.timeIntervalSince(entry.cachedAt) < cacheTTL {
            return entry.status
        }
        let computed = computeStatus(of: watch, in: context)
        cache[watch.id] = CacheEntry(status: computed, cachedAt: now)
        return computed
    }

    /// 캐시 무효화 — 측정 / wear 기록 변경 시 호출. nonisolated 로 어디서든 호출 가능.
    nonisolated static func invalidate(for watch: Watch) {
        Task { @MainActor in
            cache.removeValue(forKey: watch.id)
        }
    }

    nonisolated static func invalidateAll() {
        Task { @MainActor in cache.removeAll() }
    }

    private static func computeStatus(of watch: Watch, in context: ModelContext) -> Status {
        let lastWear = lastWearDate(of: watch, in: context)
        let lastMeasurement = watch.measurements.map(\.timestamp).max()
        let lastInteraction = [lastWear, lastMeasurement].compactMap { $0 }.max()

        let hours: Double = lastInteraction
            .map { Date().timeIntervalSince($0) / 3600 }
            ?? .greatestFiniteMagnitude

        // Quartz battery 우선 체크.
        if watch.movementType == .quartz, let due = watch.batteryNextDue {
            let daysUntilDue = Calendar.current.dateComponents([.day], from: Date(), to: due).day ?? 0
            if daysUntilDue <= 7 {
                return Status(
                    mood: .lowBattery,
                    lastInteraction: lastInteraction,
                    daysSinceInteraction: lastInteraction.map { daysSince($0) }
                )
            }
        }

        // Manual: 24h+ 미접촉이면 태엽 부족.
        if watch.movementType == .manual, hours > 24 {
            return Status(
                mood: .needsWind,
                lastInteraction: lastInteraction,
                daysSinceInteraction: lastInteraction.map { daysSince($0) }
            )
        }

        let mood: Mood
        switch hours {
        case ..<24:    mood = .energetic
        case ..<72:    mood = .happy
        case ..<168:   mood = .sleepy
        default:       mood = .dormant
        }
        return Status(
            mood: mood,
            lastInteraction: lastInteraction,
            daysSinceInteraction: lastInteraction.map { daysSince($0) }
        )
    }

    private static func lastWearDate(of watch: Watch, in context: ModelContext) -> Date? {
        let watchId = watch.id
        var descriptor = FetchDescriptor<WearLog>(
            predicate: #Predicate { log in log.watch?.id == watchId },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.date
    }

    private static func daysSince(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
    }
}
