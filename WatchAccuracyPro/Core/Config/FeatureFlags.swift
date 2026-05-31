import Foundation

/// Sprint 5 (P3-12): 서버 피처 플래그 — 앱 업데이트 없이 이벤트 on/off.
/// Phase 1: UserDefaults 기반 로컬 플래그 (서버 연동은 Phase 2).
/// 이벤트 on 시 앱 포인트 컬러 변경 + 배너 카드 표시.
@MainActor
final class FeatureFlags: ObservableObject {
    static let shared = FeatureFlags()
    private init() { load() }

    // MARK: - Flags
    @Published private(set) var seasonalEventEnabled: Bool = false
    @Published private(set) var seasonalEventTitle: String = ""
    @Published private(set) var seasonalEventColor: String = "accent"  // "accent" | "gold" | "red"

    // MARK: - Load from UserDefaults (Phase 1 로컬)
    private func load() {
        let d = UserDefaults.standard
        seasonalEventEnabled = d.bool(forKey: "ticklab.flag.seasonalEvent")
        seasonalEventTitle = d.string(forKey: "ticklab.flag.seasonalTitle") ?? ""
        seasonalEventColor = d.string(forKey: "ticklab.flag.seasonalColor") ?? "accent"
    }

    // MARK: - Debug / Remote override
    func apply(eventEnabled: Bool, title: String, color: String) {
        seasonalEventEnabled = eventEnabled
        seasonalEventTitle = title
        seasonalEventColor = color
        let d = UserDefaults.standard
        d.set(eventEnabled, forKey: "ticklab.flag.seasonalEvent")
        d.set(title, forKey: "ticklab.flag.seasonalTitle")
        d.set(color, forKey: "ticklab.flag.seasonalColor")
    }
}
