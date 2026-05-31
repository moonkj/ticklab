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
        let appGroupID = "group.com.ticklab.watchaccuracypro"
        let defaults = UserDefaults(suiteName: appGroupID)
        // Sprint 2: 큐 패턴 — 메인 앱이 launch/active 시 read & clear.
        let now = Date().timeIntervalSince1970
        defaults?.set(now, forKey: "ticklab.pendingWearToggleAt")
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
