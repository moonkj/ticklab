import XCTest
@testable import WatchAccuracyPro

/// 스마트워치 배터리 — 완충 N일 기준 경과시간 → 잔량(%) 계산. 순수 computed.
final class SmartwatchBatteryTests: XCTestCase {

    private func smartwatch(days: Double?, charged: Date?) -> Watch {
        let w = Watch(brand: "Apple", model: "Watch", movementType: .smartwatch)
        w.batteryFullChargeDays = days
        w.batteryChargedAt = charged
        return w
    }

    func test_is_smartwatch_flag() {
        XCTAssertTrue(smartwatch(days: 2, charged: Date()).isSmartwatch)
        let mech = Watch(brand: "Rolex", model: "Sub", movementType: .automatic)
        XCTAssertFalse(mech.isSmartwatch)
    }

    func test_half_drained_about_50() {
        // 완충 2일, 마지막 완충 1일 전 → 약 50%.
        let w = smartwatch(days: 2, charged: Date().addingTimeInterval(-86_400))
        let pct = w.batteryPercent ?? -1
        XCTAssertTrue((48...52).contains(pct), "expected ~50, got \(pct)")
    }

    func test_full_when_just_charged() {
        let w = smartwatch(days: 3, charged: Date())
        XCTAssertEqual(w.batteryPercent, 100)
    }

    func test_clamped_to_zero_when_overdue() {
        let w = smartwatch(days: 1, charged: Date().addingTimeInterval(-10 * 86_400))
        XCTAssertEqual(w.batteryPercent, 0)
        XCTAssertEqual(w.batteryFraction, 0)
    }

    func test_nil_when_data_missing() {
        XCTAssertNil(smartwatch(days: nil, charged: Date()).batteryFraction)
        XCTAssertNil(smartwatch(days: 2, charged: nil).batteryFraction)
        XCTAssertNil(smartwatch(days: 0, charged: Date()).batteryFraction)   // days 0 가드
    }

    func test_nil_for_non_smartwatch_even_with_data() {
        let w = Watch(brand: "Omega", model: "SMP", movementType: .quartz)
        w.batteryFullChargeDays = 2
        w.batteryChargedAt = Date()
        XCTAssertNil(w.batteryFraction)
        XCTAssertNil(w.batteryPercent)
    }

    func test_movement_type_isMeasurable() {
        XCTAssertFalse(WatchMovementType.smartwatch.isMeasurable)
        XCTAssertTrue(WatchMovementType.automatic.isMeasurable)
        XCTAssertTrue(WatchMovementType.quartz.isMeasurable)
    }
}
