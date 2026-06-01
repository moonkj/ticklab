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

    /// 커뮤니티(익명 사진 피드). 백엔드 배포 전까지 OFF — 진입점 노출 안 함. `docs/community/PLAN.md`.
    @Published private(set) var communityEnabled: Bool = false
    /// 게이팅 ON 시 무료 사용자에게 풀 노출할 최근 N장 (그 이후 인기글은 부분 흐림). 원격 조정.
    @Published private(set) var communityFreeVisibleCount: Int = 10
    /// 게이팅(부분 흐림) 자체 ON/OFF — 콜드스타트(밀도 확보) 동안은 OFF로 전부 무료.
    @Published private(set) var communityGatingEnabled: Bool = false

    // MARK: - Load from UserDefaults (Phase 1 로컬)
    private func load() {
        let d = UserDefaults.standard
        seasonalEventEnabled = d.bool(forKey: "ticklab.flag.seasonalEvent")
        seasonalEventTitle = d.string(forKey: "ticklab.flag.seasonalTitle") ?? ""
        seasonalEventColor = d.string(forKey: "ticklab.flag.seasonalColor") ?? "accent"
        communityEnabled = d.bool(forKey: "ticklab.flag.communityEnabled")
        communityGatingEnabled = d.bool(forKey: "ticklab.flag.communityGating")
        communityFreeVisibleCount = (d.object(forKey: "ticklab.flag.communityFreeN") as? Int) ?? 10
        #if DEBUG
        // DEBUG 미리보기 — 개발 빌드에서 커뮤니티 UX/UI 평가 가능. 릴리스는 백엔드 배포 후 원격 ON.
        // 백엔드 미배포 상태에선 피드 로드 실패(빈 피드)지만 화면 흐름·게이트·작성기는 확인 가능.
        communityEnabled = true
        #endif
    }

    /// 커뮤니티 플래그 조정 (디버그/원격). 백엔드 준비 후 ON.
    func applyCommunity(enabled: Bool, gating: Bool, freeVisibleCount: Int) {
        communityEnabled = enabled
        communityGatingEnabled = gating
        communityFreeVisibleCount = max(1, freeVisibleCount)
        let d = UserDefaults.standard
        d.set(communityEnabled, forKey: "ticklab.flag.communityEnabled")
        d.set(communityGatingEnabled, forKey: "ticklab.flag.communityGating")
        d.set(communityFreeVisibleCount, forKey: "ticklab.flag.communityFreeN")
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
