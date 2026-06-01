import XCTest
@testable import WatchAccuracyPro

/// `MagneticFieldService.level(microTesla:)` 분류 임계 + `Level` 키 매핑 회귀 보호.
/// 순수 산술/매핑만 — CMMotionManager 미사용.
/// `MagneticFieldService` 가 `@MainActor` 라서 테스트 클래스도 `@MainActor`.
@MainActor
final class MagneticFieldLevelTests: XCTestCase {

    // MARK: - level(microTesla:) 경계

    func test_below_100_is_normal() {
        XCTAssertEqual(MagneticFieldService.level(microTesla: 0), .normal)
        XCTAssertEqual(MagneticFieldService.level(microTesla: 50), .normal)
        XCTAssertEqual(MagneticFieldService.level(microTesla: 99.9), .normal)
    }

    func test_100_to_300_is_slightly_high() {
        // 100 은 normal 상한(..<100) 밖 → slightlyHigh 시작.
        XCTAssertEqual(MagneticFieldService.level(microTesla: 100), .slightlyHigh)
        XCTAssertEqual(MagneticFieldService.level(microTesla: 299.9), .slightlyHigh)
    }

    func test_300_to_1000_is_high() {
        XCTAssertEqual(MagneticFieldService.level(microTesla: 300), .high)
        XCTAssertEqual(MagneticFieldService.level(microTesla: 999.9), .high)
    }

    func test_1000_and_above_is_very_high() {
        XCTAssertEqual(MagneticFieldService.level(microTesla: 1000), .veryHigh)
        XCTAssertEqual(MagneticFieldService.level(microTesla: 5000), .veryHigh)
    }

    func test_negative_values_use_absolute_value() {
        // raw magnetometer 는 음수 가능 — abs 처리.
        XCTAssertEqual(MagneticFieldService.level(microTesla: -50), .normal)
        XCTAssertEqual(MagneticFieldService.level(microTesla: -250), .slightlyHigh)
        XCTAssertEqual(MagneticFieldService.level(microTesla: -500), .high)
        XCTAssertEqual(MagneticFieldService.level(microTesla: -2000), .veryHigh)
    }

    // MARK: - Level 키 매핑

    func test_localization_keys_are_distinct_and_stable() {
        let cases: [MagneticFieldService.Level] = [.normal, .slightlyHigh, .high, .veryHigh]
        let keys = cases.map(\.localizationKey)
        XCTAssertEqual(Set(keys).count, cases.count, "localizationKey 는 모두 distinct")
        XCTAssertEqual(MagneticFieldService.Level.normal.localizationKey, "magnetic.level.normal")
        XCTAssertEqual(MagneticFieldService.Level.slightlyHigh.localizationKey, "magnetic.level.slightly_high")
        XCTAssertEqual(MagneticFieldService.Level.high.localizationKey, "magnetic.level.high")
        XCTAssertEqual(MagneticFieldService.Level.veryHigh.localizationKey, "magnetic.level.very_high")
    }

    func test_verdict_keys_are_distinct_and_stable() {
        let cases: [MagneticFieldService.Level] = [.normal, .slightlyHigh, .high, .veryHigh]
        let keys = cases.map(\.verdictKey)
        XCTAssertEqual(Set(keys).count, cases.count, "verdictKey 는 모두 distinct")
        XCTAssertEqual(MagneticFieldService.Level.normal.verdictKey, "magnetic.verdict.normal")
        XCTAssertEqual(MagneticFieldService.Level.slightlyHigh.verdictKey, "magnetic.verdict.slightly_high")
        XCTAssertEqual(MagneticFieldService.Level.high.verdictKey, "magnetic.verdict.high")
        XCTAssertEqual(MagneticFieldService.Level.veryHigh.verdictKey, "magnetic.verdict.very_high")
    }

    func test_raw_values_are_stable() {
        XCTAssertEqual(MagneticFieldService.Level.normal.rawValue, "normal")
        XCTAssertEqual(MagneticFieldService.Level.slightlyHigh.rawValue, "slightlyHigh")
        XCTAssertEqual(MagneticFieldService.Level.high.rawValue, "high")
        XCTAssertEqual(MagneticFieldService.Level.veryHigh.rawValue, "veryHigh")
    }
}
