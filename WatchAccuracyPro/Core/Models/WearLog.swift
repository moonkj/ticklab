import Foundation
import SwiftData

/// 시계 착용 데일리 로그.
/// 사용자가 매일 "오늘 어떤 시계 찼는지" 기록하는 가벼운 entry — 측정 / 일기와 별개.
/// 통계 탭에서 차트로 누적 보기 (시계별 / 기간별).
///
/// Pivot Addendum 4-axis: Measure / Maintain / Journal / Journey 의 Journey 일부.
@Model
final class WearLog {
    @Attribute(.unique) var id: UUID
    var watch: Watch?
    /// 해당 일자 (시작 시각). 하루에 한 시계 = 1 log (Unique constraint 는 application logic 에서).
    var date: Date
    /// 자동/수동 구분. 측정 시 자동 generation 가능.
    var isAuto: Bool
    /// 짧은 메모 (선택).
    var note: String

    init(
        id: UUID = UUID(),
        watch: Watch? = nil,
        date: Date = .init(),
        isAuto: Bool = false,
        note: String = ""
    ) {
        self.id = id
        self.watch = watch
        // Day-granularity 로 normalize.
        self.date = Calendar.current.startOfDay(for: date)
        self.isAuto = isAuto
        self.note = note
    }
}

extension WearLog: Identifiable {}
