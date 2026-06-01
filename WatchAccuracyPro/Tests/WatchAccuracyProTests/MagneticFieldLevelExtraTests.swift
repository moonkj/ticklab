import XCTest
@testable import WatchAccuracyPro

/// 커버리지 보강(추가) — MagneticFieldService.Level 의 CaseIterable + 미검증 경계.
/// MagneticFieldLevelTests 가 다루는 임계/키 매핑 단언과 중복하지 않는다.
/// MagneticFieldService 가 @MainActor 라서 테스트 클래스도 @MainActor.
@MainActor
final class MagneticFieldLevelExtraTests: XCTestCase {

    // MARK: - CaseIterable

    func test_allCases_order_and_count() {
        XCTAssertEqual(MagneticFieldService.Level.allCases,
                       [.normal, .slightlyHigh, .high, .veryHigh])
    }

    // MARK: - level(microTesla:) 미검증 경계/극단

    func test_level_exact_99_999_still_normal() {
        // ..<100 상한 직전.
        XCTAssertEqual(MagneticFieldService.level(microTesla: 99.999), .normal)
    }

    func test_level_exact_999_999_still_high() {
        // ..<1000 상한 직전.
        XCTAssertEqual(MagneticFieldService.level(microTesla: 999.999), .high)
    }

    func test_level_extreme_value_is_very_high() {
        XCTAssertEqual(MagneticFieldService.level(microTesla: 1_000_000), .veryHigh)
    }

    func test_level_negative_extreme_uses_abs() {
        // 큰 음수 → abs → veryHigh.
        XCTAssertEqual(MagneticFieldService.level(microTesla: -1_000_000), .veryHigh)
        // 음수 경계: -100 → abs 100 → slightlyHigh (..<100 밖).
        XCTAssertEqual(MagneticFieldService.level(microTesla: -100), .slightlyHigh)
    }

    func test_level_zero_is_normal() {
        XCTAssertEqual(MagneticFieldService.level(microTesla: 0.0), .normal)
    }
}
