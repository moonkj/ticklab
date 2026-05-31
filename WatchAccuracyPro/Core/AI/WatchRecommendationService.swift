import Foundation
import SwiftData

/// Sprint 5 (P2-15): 오늘의 시계 규칙 기반 온디바이스 추천.
/// 외부 API 없음. 날씨/캘린더 연동 없이 착용 이력만으로 추천.
/// 규칙 우선순위: ① 오래 안 찬 시계 → ② 착용 ROI 가장 낮은 시계 (가성비 높이기)
@MainActor
enum WatchRecommendationService {

    struct Recommendation {
        let watch: Watch
        let reason: LocalizedStringResource
    }

    static func recommend(from watches: [Watch], wearLogs: [WearLog]) -> Recommendation? {
        guard !watches.isEmpty else { return nil }

        // 오늘 착용한 시계 제외
        let today = Calendar.current.startOfDay(for: Date())
        let wornTodayIds = Set(wearLogs.filter {
            Calendar.current.startOfDay(for: $0.date) == today
        }.compactMap { $0.watch?.id })

        let candidates = watches.filter { !wornTodayIds.contains($0.id) }
        guard !candidates.isEmpty else { return nil }

        // 마지막 착용일 기준 — 가장 오래 안 찬 시계
        let lastWornByWatch: [UUID: Date] = Dictionary(
            wearLogs.compactMap { log -> (UUID, Date)? in
                guard let id = log.watch?.id else { return nil }
                return (id, log.date)
            },
            uniquingKeysWith: { max($0, $1) }
        )

        // 한 번도 안 찬 시계 우선
        let neverWorn = candidates.filter { lastWornByWatch[$0.id] == nil }
        if let pick = neverWorn.first {
            return Recommendation(watch: pick, reason: "recommendation.reason.never_worn")
        }

        // 가장 오래 안 찬 시계
        let sorted = candidates.sorted { a, b in
            let la = lastWornByWatch[a.id] ?? .distantPast
            let lb = lastWornByWatch[b.id] ?? .distantPast
            return la < lb
        }
        guard let oldest = sorted.first else { return nil }
        let last = lastWornByWatch[oldest.id] ?? .distantPast
        let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        if days >= 7 {
            return Recommendation(watch: oldest, reason: "recommendation.reason.long_unworn")
        }
        // 착용 ROI — purchasePrice 있는 시계 중 가장 착용 횟수 적은 것
        let roiCandidates = candidates.filter { $0.purchasePrice != nil }
        if !roiCandidates.isEmpty {
            let wearCounts: [UUID: Int] = Dictionary(
                wearLogs.compactMap { log -> (UUID, Int)? in
                    guard let id = log.watch?.id else { return nil }
                    return (id, 1)
                },
                uniquingKeysWith: +
            )
            let leastWorn = roiCandidates.min(by: {
                (wearCounts[$0.id] ?? 0) < (wearCounts[$1.id] ?? 0)
            })
            if let pick = leastWorn {
                return Recommendation(watch: pick, reason: "recommendation.reason.low_roi")
            }
        }
        return Recommendation(watch: sorted.first!, reason: "recommendation.reason.rotation")
    }
}
