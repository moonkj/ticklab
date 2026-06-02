import Foundation
import SwiftData

/// Sprint 14 (S3+S4, R3 리텐션): 주간 컨디션 체크 + "오늘 할 일" 데이터.
/// 마지막 측정 후 N일 지난 기계식 시계를 "점검 대기"로 모은다. 신규 화면 없이 TodayView 카드에 사용.
@MainActor
enum WeeklyCheckService {
    /// 점검 권장 기준 (일). 측정 앱의 자연 주기 = 주 단위.
    static let staleDays = 7

    struct TodoSummary {
        let needsCheck: [Watch]      // 측정 7일+ 경과 기계식
        let neverMeasured: [Watch]   // 한 번도 측정 안 함
        var total: Int { needsCheck.count + neverMeasured.count }
    }

    static func summary(watches: [Watch]) -> TodoSummary {
        let now = Date()
        var needsCheck: [Watch] = []
        var never: [Watch] = []
        // Round 173: 쿼츠 + 스마트워치(애플워치 등) 제외 — rate 측정 대상 아님(생활기록용).
        for w in watches where w.movementType != .quartz && w.movementType.isMeasurable {
            guard let last = w.measurements.map(\.timestamp).max() else {
                never.append(w)
                continue
            }
            let days = Calendar.current.dateComponents([.day], from: last, to: now).day ?? 0
            if days >= staleDays { needsCheck.append(w) }
        }
        // 오래된 순
        needsCheck.sort {
            ($0.measurements.map(\.timestamp).max() ?? .distantPast) <
            ($1.measurements.map(\.timestamp).max() ?? .distantPast)
        }
        return TodoSummary(needsCheck: needsCheck, neverMeasured: never)
    }
}
