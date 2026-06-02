import XCTest
@testable import WatchAccuracyPro

/// `ClockCalibrationService` 순수 수학 함수 보완 회귀 보호.
///
/// 기존 `ClockCalibrationServiceTests` 는 기본 케이스(fast/slow/outlier/baseline/jitter)를 커버.
/// 이 파일은 **경계 조건·에지 케이스** 에 집중한다:
///   - `regressionPpm`: 배열 길이 불일치, 정확히 baseline 경계, 상수 mono(기울기 0), ±maxAbsPpm 경계
///   - `driftPpm`: zero trueElapsed, trueElapsed 정확히 minBaseline, ±maxAbsPpm 경계
///   - `correctionFactor`: 주입된 ppm 으로 수식 검증
/// 네트워크/시스템 시각 의존 없음 — 순수 산술만.
final class ClockCalibrationMathTests: XCTestCase {

    // MARK: - 헬퍼

    /// 진짜시간 배열 ts 에 대해 mono = offset + (1 + ppm×1e-6)·t 관계를 만족하는 점들을 생성.
    private func linearPoints(ppm: Double,
                               ts: [Double],
                               offset: Double = 500.0) -> (monos: [Double], trues: [Double]) {
        (monos: ts.map { offset + (1.0 + ppm * 1e-6) * $0 }, trues: ts)
    }

    // MARK: - regressionPpm: 배열 불일치 → nil

    func test_regression_mismatched_array_lengths_returns_nil() {
        // monos 3개, trues 4개 → 입력 불량 → nil
        let monos = [100.0, 200.0, 300.0]
        let trues = [0.0,   600.0, 1200.0, 1800.0]
        XCTAssertNil(ClockCalibrationService.regressionPpm(monos: monos, trues: trues,
                                                           minBaseline: 120, maxAbsPpm: 200))
    }

    func test_regression_monos_longer_than_trues_returns_nil() {
        let monos = [0.0, 600.0, 1200.0, 1800.0]
        let trues = [0.0, 600.0, 1200.0]
        XCTAssertNil(ClockCalibrationService.regressionPpm(monos: monos, trues: trues,
                                                           minBaseline: 120, maxAbsPpm: 200))
    }

    // MARK: - regressionPpm: 정확히 baseline 경계

    func test_regression_span_exactly_at_baseline_passes() {
        // span == minBaseline 정확 일치 → 통과해야 함 (>=)
        let p = linearPoints(ppm: 20, ts: [0, 60, 120])  // span = 120
        let result = ClockCalibrationService.regressionPpm(monos: p.monos, trues: p.trues,
                                                           minBaseline: 120, maxAbsPpm: 200)
        XCTAssertNotNil(result, "span == minBaseline 일 때 nil 이면 안 됨")
        XCTAssertEqual(result ?? .nan, 20, accuracy: 0.5)
    }

    func test_regression_span_one_second_below_baseline_returns_nil() {
        // span = minBaseline - 1 → nil
        let p = linearPoints(ppm: 20, ts: [0, 60, 119])  // span = 119 < 120
        XCTAssertNil(ClockCalibrationService.regressionPpm(monos: p.monos, trues: p.trues,
                                                           minBaseline: 120, maxAbsPpm: 200))
    }

    // MARK: - regressionPpm: 모든 mono 값 동일 (기울기 0 → ppm ≈ −1e6)

    func test_regression_constant_monos_outlier_rejected() {
        // mono 가 모두 같으면 기울기 ≈ 0 → ppm ≈ (0−1)×1e6 = −1,000,000 → maxAbsPpm 초과 → nil
        let trues = [0.0, 600.0, 1200.0]
        let monos = [500.0, 500.0, 500.0]
        XCTAssertNil(ClockCalibrationService.regressionPpm(monos: monos, trues: trues,
                                                           minBaseline: 120, maxAbsPpm: 200),
                     "상수 mono 는 outlier 로 기각돼야 함")
    }

    // MARK: - regressionPpm: ±maxAbsPpm 정확 경계

    func test_regression_ppm_exactly_at_maxAbsPpm_is_accepted() {
        // ppm 정확히 200 → |ppm| <= maxAbsPpm (200 <= 200) → nil 이면 안 됨
        let p = linearPoints(ppm: 200, ts: [0, 600, 1200, 1800])
        let result = ClockCalibrationService.regressionPpm(monos: p.monos, trues: p.trues,
                                                           minBaseline: 1800, maxAbsPpm: 200)
        XCTAssertNotNil(result, "ppm == maxAbsPpm 일 때 허용돼야 함")
        XCTAssertEqual(result ?? .nan, 200, accuracy: 1)
    }

    func test_regression_ppm_just_above_maxAbsPpm_is_rejected() {
        // ppm 200.1 > 200 → nil
        let p = linearPoints(ppm: 200.1, ts: [0, 600, 1200, 1800])
        XCTAssertNil(ClockCalibrationService.regressionPpm(monos: p.monos, trues: p.trues,
                                                           minBaseline: 1800, maxAbsPpm: 200),
                     "ppm > maxAbsPpm 은 기각돼야 함")
    }

    func test_regression_negative_ppm_exactly_at_minus_maxAbsPpm_accepted() {
        let p = linearPoints(ppm: -200, ts: [0, 600, 1200, 1800])
        let result = ClockCalibrationService.regressionPpm(monos: p.monos, trues: p.trues,
                                                           minBaseline: 1800, maxAbsPpm: 200)
        XCTAssertNotNil(result)
        XCTAssertEqual(result ?? .nan, -200, accuracy: 1)
    }

    // MARK: - regressionPpm: 두 점 최소 조건 경계

    func test_regression_two_points_with_sufficient_span_recovers_ppm() {
        // 정확히 2개 점 — 최소 요건 충족. OLS 2점 = 완벽 직선이므로 정확히 복원.
        let p = linearPoints(ppm: 50, ts: [0, 300])   // span 300 >= minBaseline 120
        let result = ClockCalibrationService.regressionPpm(monos: p.monos, trues: p.trues,
                                                           minBaseline: 120, maxAbsPpm: 200)
        XCTAssertNotNil(result)
        XCTAssertEqual(result ?? .nan, 50, accuracy: 0.5)
    }

    func test_regression_one_point_returns_nil() {
        XCTAssertNil(ClockCalibrationService.regressionPpm(monos: [500],
                                                           trues: [0],
                                                           minBaseline: 120, maxAbsPpm: 200))
    }

    // MARK: - driftPpm: zero / negative trueElapsed

    func test_driftPpm_zero_trueElapsed_returns_nil() {
        // trueElapsed 0 → monotonicElapsed > 0 조건도 충족하지만
        // guard trueElapsed >= minBaseline 에서 먼저 탈락 (0 < minBaseline)
        XCTAssertNil(ClockCalibrationService.driftPpm(monotonicElapsed: 0,
                                                      trueElapsed: 0,
                                                      minBaseline: 3600, maxAbsPpm: 200))
    }

    func test_driftPpm_negative_monotonicElapsed_returns_nil() {
        // guard monotonicElapsed > 0 → 음수는 nil
        XCTAssertNil(ClockCalibrationService.driftPpm(monotonicElapsed: -1,
                                                      trueElapsed: 7200,
                                                      minBaseline: 3600, maxAbsPpm: 200))
    }

    // MARK: - driftPpm: 정확히 minBaseline 경계

    func test_driftPpm_exactly_at_minBaseline_passes() {
        // trueElapsed == minBaseline → 통과 (>=)
        let dTrue = 3600.0
        let dMono = dTrue * (1 + 30e-6)
        let result = ClockCalibrationService.driftPpm(monotonicElapsed: dMono,
                                                      trueElapsed: dTrue,
                                                      minBaseline: 3600, maxAbsPpm: 200)
        XCTAssertNotNil(result, "trueElapsed == minBaseline 일 때 통과해야 함")
        XCTAssertEqual(result ?? .nan, 30, accuracy: 0.5)
    }

    func test_driftPpm_just_below_minBaseline_returns_nil() {
        let dTrue = 3599.0  // 3600 - 1
        let dMono = dTrue * (1 + 30e-6)
        XCTAssertNil(ClockCalibrationService.driftPpm(monotonicElapsed: dMono,
                                                      trueElapsed: dTrue,
                                                      minBaseline: 3600, maxAbsPpm: 200))
    }

    // MARK: - driftPpm: ±maxAbsPpm 경계

    func test_driftPpm_exactly_at_maxAbsPpm_is_accepted() {
        let dTrue = 7200.0
        let dMono = dTrue * (1 + 200e-6)  // 정확히 +200ppm
        let result = ClockCalibrationService.driftPpm(monotonicElapsed: dMono,
                                                      trueElapsed: dTrue,
                                                      minBaseline: 3600, maxAbsPpm: 200)
        XCTAssertNotNil(result, "ppm == maxAbsPpm 은 허용돼야 함")
        XCTAssertEqual(result ?? .nan, 200, accuracy: 0.5)
    }

    func test_driftPpm_just_above_maxAbsPpm_is_rejected() {
        let dTrue = 7200.0
        let dMono = dTrue * (1 + 201e-6)  // 201ppm > 200
        XCTAssertNil(ClockCalibrationService.driftPpm(monotonicElapsed: dMono,
                                                      trueElapsed: dTrue,
                                                      minBaseline: 3600, maxAbsPpm: 200))
    }

    // MARK: - correctionFactor 수식 검증

    // correctionFactor = 1 / (1 + driftPpm / 1_000_000)
    // driftPpm 은 UserDefaults 에서 읽는다. 고유한 suiteName 으로 격리 인스턴스를 만들어
    // UserDefaults 에 직접 값을 쓴 뒤 correctionFactor 를 읽어 수식을 검증한다.

    func test_correctionFactor_zero_ppm_equals_one() {
        let svc = ClockCalibrationService(
            defaults: UserDefaults(suiteName: "test.ccmath.zero.\(UUID().uuidString)")!
        )
        XCTAssertEqual(svc.correctionFactor, 1.0, accuracy: 1e-12)
    }

    func test_correctionFactor_positive_ppm_less_than_one() {
        // +100ppm 발진기 → factor = 1/(1.0001) < 1 → beatSec 줄어 rate 보정
        let suite = "test.ccmath.pos.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        ud.set(100.0, forKey: "ticklab.clockcal.driftPpm")
        let svc = ClockCalibrationService(defaults: ud)
        let expected = 1.0 / (1.0 + 100.0 / 1_000_000.0)
        XCTAssertEqual(svc.correctionFactor, expected, accuracy: 1e-10)
        XCTAssertLessThan(svc.correctionFactor, 1.0)
    }

    func test_correctionFactor_negative_ppm_greater_than_one() {
        // −100ppm → factor = 1/(0.9999) > 1
        let suite = "test.ccmath.neg.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        ud.set(-100.0, forKey: "ticklab.clockcal.driftPpm")
        let svc = ClockCalibrationService(defaults: ud)
        let expected = 1.0 / (1.0 + (-100.0) / 1_000_000.0)
        XCTAssertEqual(svc.correctionFactor, expected, accuracy: 1e-10)
        XCTAssertGreaterThan(svc.correctionFactor, 1.0)
    }

    func test_correctionFactor_known_ppm_roundtrip() {
        // +56ppm (기존 테스트 케이스 레퍼런스값) — 보정 방향 회귀
        let suite = "test.ccmath.rt.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        ud.set(56.0, forKey: "ticklab.clockcal.driftPpm")
        let svc = ClockCalibrationService(defaults: ud)
        // factor 는 1 보다 작아야 하고 1에 아주 가까워야 함
        let factor = svc.correctionFactor
        XCTAssertLessThan(factor, 1.0)
        XCTAssertGreaterThan(factor, 0.999)
        XCTAssertEqual(factor, 1.0 / (1.0 + 56e-6), accuracy: 1e-12)
    }

    // MARK: - isCalibrated 상태 검증

    func test_isCalibrated_false_when_driftPpm_zero() {
        let svc = ClockCalibrationService(
            defaults: UserDefaults(suiteName: "test.ccmath.cal0.\(UUID().uuidString)")!
        )
        XCTAssertFalse(svc.isCalibrated)
    }

    func test_isCalibrated_true_when_nonzero_ppm_stored() {
        let suite = "test.ccmath.cal1.\(UUID().uuidString)"
        let ud = UserDefaults(suiteName: suite)!
        ud.set(42.0, forKey: "ticklab.clockcal.driftPpm")
        let svc = ClockCalibrationService(defaults: ud)
        XCTAssertTrue(svc.isCalibrated)
    }

    // MARK: - minBaselineSeconds / maxAbsPpm / maxPoints 상수 회귀

    func test_constants_are_within_expected_ranges() {
        // 상수가 실수로 변경되면 회귀 잡히도록
        XCTAssertEqual(ClockCalibrationService.minBaselineSeconds, 120, accuracy: 0.001)
        XCTAssertEqual(ClockCalibrationService.maxAbsPpm, 200, accuracy: 0.001)
        XCTAssertEqual(ClockCalibrationService.maxPoints, 60)
        XCTAssertEqual(ClockCalibrationService.minSpacingSeconds, 15, accuracy: 0.001)
    }
}
