import AppIntents
import Foundation
import WidgetKit

/// Sprint 2 (P1-1): 위젯/홈 화면에서 즉시 착용 토글.
/// `perform()` 은 App Group UserDefaults 에 토글 의도만 기록 → 메인 앱이 다음 launch 시 처리.
/// 이렇게 분리한 이유: 위젯 extension 에서 SwiftData ModelContext 직접 변경은 sandboxing risk.
struct WearToggleIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle today's wear"
    static var description = IntentDescription("Mark the most recently measured watch as worn today.")

    func perform() async throws -> some IntentResult {
        // 낙관적: 현재 "오늘 착용" 상태를 뒤집어 즉시 위젯에 반영(앱 미실행 중에도 버튼이 바로 바뀜).
        let current = SharedSnapshotStore.readWornToday()
        SharedSnapshotStore.writeWornToday(!current)
        // 앱이 launch/active 시 실제 WearLog 를 이 desired 상태로 reconcile 하도록 신호(큐).
        SharedSnapshotStore.defaults?.set(Date().timeIntervalSince1970, forKey: SharedSnapshotStore.pendingWearToggleKey)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
