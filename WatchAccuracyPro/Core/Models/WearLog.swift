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
    /// Sprint 4 (P2-18): 이벤트 태그. JSON 문자열 배열로 저장 (SwiftData migration safe).
    /// 예: ["비즈니스", "포멀"] — 프리셋 또는 커스텀 입력.
    var tagsRaw: String = "[]"

    /// 파싱된 태그 배열 접근자.
    var tags: [String] {
        get {
            (try? JSONDecoder().decode([String].self, from: Data(tagsRaw.utf8))) ?? []
        }
        set {
            tagsRaw = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]"
        }
    }

    /// Sprint 4 (P3-3): 하이라이트 플래그 — 특별한 순간 표시.
    var isHighlight: Bool = false

    init(
        id: UUID = UUID(),
        watch: Watch? = nil,
        date: Date = .init(),
        isAuto: Bool = false,
        note: String = "",
        tags: [String] = [],
        isHighlight: Bool = false
    ) {
        self.id = id
        self.watch = watch
        // Day-granularity 로 normalize.
        self.date = Calendar.current.startOfDay(for: date)
        self.isAuto = isAuto
        self.note = note
        self.tagsRaw = (try? String(data: JSONEncoder().encode(tags), encoding: .utf8)) ?? "[]"
        self.isHighlight = isHighlight
    }
}

/// Sprint 4 (P2-18): 이벤트 태그 프리셋.
enum WearTag: String, CaseIterable, Identifiable, Sendable {
    case business   = "비즈니스"
    case casual     = "캐주얼"
    case formal     = "포멀"
    case travel     = "여행"
    case special    = "특별한 날"
    case sports     = "스포츠"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .business: return "briefcase"
        case .casual:   return "tshirt"
        case .formal:   return "wineglass"   // "suit" 는 실존하지 않는 SF Symbol → 빈 칸. 유효 심볼로 교체.
        case .travel:   return "airplane"
        case .special:  return "star"
        case .sports:   return "figure.run"
        }
    }

    /// 화면 표시용 현지화 이름. rawValue(저장 키)는 절대 변경 금지.
    var displayName: String {
        switch self {
        case .business: return String(localized: "wear.tag.business")
        case .casual:   return String(localized: "wear.tag.casual")
        case .formal:   return String(localized: "wear.tag.formal")
        case .travel:   return String(localized: "wear.tag.travel")
        case .special:  return String(localized: "wear.tag.special")
        case .sports:   return String(localized: "wear.tag.sports")
        }
    }

    /// rawValue 문자열로부터 displayName 을 반환. 프리셋이 아닌 커스텀 태그는 그대로 반환.
    static func displayName(for rawValue: String) -> String {
        WearTag(rawValue: rawValue)?.displayName ?? rawValue
    }
}

extension WearLog: Identifiable {}
