import Foundation
import SwiftData

/// Sprint 4 (P2-17): TickLab Wrapped 연간 리포트 데이터 계산.
/// 뷰 독립 — 순수 데이터 레이어. UI 는 WrappedView 에서 담당.
@MainActor
struct WrappedReportData {
    let year: Int
    let totalWears: Int
    let mostWornWatch: (watch: Watch, count: Int)?
    let leastWornWatch: (watch: Watch, count: Int)?
    let totalMeasurements: Int
    let avgRateSecondsPerDay: Double?
    let newWatchesAdded: Int
    let topTag: String?
    let highlightCount: Int

    static func generate(year: Int, context: ModelContext) -> WrappedReportData {
        let cal = Calendar.current
        guard let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
            return empty(year: year)
        }

        // 착용 기록
        let wearDesc = FetchDescriptor<WearLog>(predicate: #Predicate { $0.date >= start && $0.date < end })
        let wears = (try? context.fetch(wearDesc)) ?? []
        let totalWears = wears.count

        // 시계별 착용 수
        var wearByWatch: [UUID: (Watch, Int)] = [:]
        for log in wears {
            guard let w = log.watch else { continue }
            wearByWatch[w.id] = (w, (wearByWatch[w.id]?.1 ?? 0) + 1)
        }
        let sorted = wearByWatch.values.sorted { $0.1 > $1.1 }
        let mostWorn  = sorted.first.map { (watch: $0.0, count: $0.1) }
        let leastWorn = sorted.last.map  { (watch: $0.0, count: $0.1) }

        // 측정
        let measDesc = FetchDescriptor<WatchMeasurement>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end }
        )
        let meas = (try? context.fetch(measDesc)) ?? []
        let avgRate: Double? = meas.isEmpty ? nil
            : meas.map(\.rateSecondsPerDay).reduce(0, +) / Double(meas.count)

        // 신규 시계
        let watchDesc = FetchDescriptor<Watch>(predicate: #Predicate { $0.createdAt >= start && $0.createdAt < end })
        let newWatches = (try? context.fetchCount(watchDesc)) ?? 0

        // 태그 집계
        let allTags = wears.flatMap { $0.tags }
        let tagCounts = Dictionary(allTags.map { ($0, 1) }, uniquingKeysWith: +)
        let topTag = tagCounts.max(by: { $0.value < $1.value })?.key

        // 하이라이트
        let highlights = wears.filter { $0.isHighlight }.count

        return WrappedReportData(
            year: year,
            totalWears: totalWears,
            mostWornWatch: mostWorn,
            leastWornWatch: leastWorn,
            totalMeasurements: meas.count,
            avgRateSecondsPerDay: avgRate,
            newWatchesAdded: newWatches,
            topTag: topTag,
            highlightCount: highlights
        )
    }

    private static func empty(year: Int) -> WrappedReportData {
        WrappedReportData(year: year, totalWears: 0, mostWornWatch: nil, leastWornWatch: nil,
                         totalMeasurements: 0, avgRateSecondsPerDay: nil,
                         newWatchesAdded: 0, topTag: nil, highlightCount: 0)
    }
}
