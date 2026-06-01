import XCTest
@testable import WatchAccuracyPro

/// PURE-ish 커버리지: FeatureFlags — UserDefaults 백킹 로컬 피처 플래그.
/// FeatureFlags 는 @MainActor 싱글톤(.shared)이므로 클래스도 @MainActor.
/// setter(apply / applyCommunity)가 published 값과 UserDefaults 를 함께 갱신하는지 검증.
/// 테스트가 쓴 "ticklab.flag.*" 키는 tearDown 에서 정리.
@MainActor
final class FeatureFlagsTests: XCTestCase {

    private let keys = [
        "ticklab.flag.seasonalEvent",
        "ticklab.flag.seasonalTitle",
        "ticklab.flag.seasonalColor",
        "ticklab.flag.communityEnabled",
        "ticklab.flag.communityGating",
        "ticklab.flag.communityFreeN",
    ]

    override func tearDown() {
        let d = UserDefaults.standard
        keys.forEach { d.removeObject(forKey: $0) }
        super.tearDown()
    }

    // MARK: - apply(eventEnabled:title:color:)

    func test_apply_setsPublishedValues() {
        let flags = FeatureFlags.shared
        flags.apply(eventEnabled: true, title: "Spring Fest", color: "gold")
        XCTAssertTrue(flags.seasonalEventEnabled)
        XCTAssertEqual(flags.seasonalEventTitle, "Spring Fest")
        XCTAssertEqual(flags.seasonalEventColor, "gold")
    }

    func test_apply_persistsToUserDefaults() {
        FeatureFlags.shared.apply(eventEnabled: true, title: "Holiday", color: "red")
        let d = UserDefaults.standard
        XCTAssertTrue(d.bool(forKey: "ticklab.flag.seasonalEvent"))
        XCTAssertEqual(d.string(forKey: "ticklab.flag.seasonalTitle"), "Holiday")
        XCTAssertEqual(d.string(forKey: "ticklab.flag.seasonalColor"), "red")
    }

    func test_apply_canDisable() {
        let flags = FeatureFlags.shared
        flags.apply(eventEnabled: true, title: "On", color: "accent")
        flags.apply(eventEnabled: false, title: "", color: "accent")
        XCTAssertFalse(flags.seasonalEventEnabled)
        XCTAssertEqual(flags.seasonalEventTitle, "")
    }

    // MARK: - applyCommunity(enabled:gating:freeVisibleCount:)

    func test_applyCommunity_setsPublishedValues() {
        let flags = FeatureFlags.shared
        flags.applyCommunity(enabled: true, gating: true, freeVisibleCount: 25)
        XCTAssertTrue(flags.communityEnabled)
        XCTAssertTrue(flags.communityGatingEnabled)
        XCTAssertEqual(flags.communityFreeVisibleCount, 25)
    }

    func test_applyCommunity_clampsFreeVisibleCountToAtLeastOne() {
        let flags = FeatureFlags.shared
        flags.applyCommunity(enabled: true, gating: false, freeVisibleCount: 0)
        XCTAssertEqual(flags.communityFreeVisibleCount, 1, "freeVisibleCount 는 최소 1 로 clamp")

        flags.applyCommunity(enabled: true, gating: false, freeVisibleCount: -5)
        XCTAssertEqual(flags.communityFreeVisibleCount, 1)
    }

    func test_applyCommunity_persistsToUserDefaults() {
        FeatureFlags.shared.applyCommunity(enabled: true, gating: true, freeVisibleCount: 12)
        let d = UserDefaults.standard
        XCTAssertTrue(d.bool(forKey: "ticklab.flag.communityEnabled"))
        XCTAssertTrue(d.bool(forKey: "ticklab.flag.communityGating"))
        XCTAssertEqual(d.integer(forKey: "ticklab.flag.communityFreeN"), 12)
    }

    func test_applyCommunity_canToggleGatingOff() {
        let flags = FeatureFlags.shared
        flags.applyCommunity(enabled: true, gating: true, freeVisibleCount: 10)
        flags.applyCommunity(enabled: true, gating: false, freeVisibleCount: 10)
        XCTAssertFalse(flags.communityGatingEnabled)
    }
}
