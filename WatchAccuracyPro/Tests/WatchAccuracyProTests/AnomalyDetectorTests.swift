import XCTest
@testable import WatchAccuracyPro

/// 스트림 D: `AnomalyDetector` 순수 함수 회귀 보호.
/// median+MAD 기반 급변 탐지·사유 분류·floor·게이트를 검증한다. 시간/네트워크 의존 없음.
final class AnomalyDetectorTests: XCTestCase {

    // MARK: - 과거 표본 부족 → nil

    func test_insufficient_history_returns_nil() {
        // history 3개 < minHistoryCount(4).
        let result = AnomalyDetector.detect(
            historyRates: [0, 1, -1],
            historyBeatErrors: [0.2, 0.3, 0.2],
            latestRate: 100,
            latestBeatError: 0.2
        )
        XCTAssertNil(result)
    }

    // MARK: - 정상 변동 → nil

    func test_normal_reading_returns_nil() {
        // 과거 ±2 s/d, 신규 +1 → 정상.
        let result = AnomalyDetector.detect(
            historyRates: [-2, 1, 0, 2, -1, 1],
            historyBeatErrors: [0.3, 0.2, 0.3, 0.2, 0.3, 0.2],
            latestRate: 1,
            latestBeatError: 0.25
        )
        XCTAssertNil(result)
    }

    func test_within_floor_not_flagged() {
        // 과거가 거의 일치(MAD≈0)지만 신규 +7 s/d 는 floor(8) 이내 → 정상.
        let result = AnomalyDetector.detect(
            historyRates: [0, 0, 0, 1, -1, 0],
            historyBeatErrors: [0.2, 0.2, 0.2, 0.2, 0.2, 0.2],
            latestRate: 7,
            latestBeatError: 0.2
        )
        XCTAssertNil(result)
    }

    // MARK: - rate 급증 → 자성화 의심

    func test_large_positive_jump_is_magnetization() {
        // 과거 0 근처, 신규 +120 → 자성화.
        let result = AnomalyDetector.detect(
            historyRates: [-1, 0, 1, 0, -1, 1],
            historyBeatErrors: [0.3, 0.3, 0.3, 0.3, 0.3, 0.3],
            latestRate: 120,
            latestBeatError: 0.3
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.reason, .suspectMagnetization)
        XCTAssertGreaterThan(result?.deviationSigma ?? 0, 0)
        XCTAssertEqual(result?.latestRate, 120)
    }

    // MARK: - rate 급감 → 충격 의심

    func test_large_negative_jump_is_shock() {
        let result = AnomalyDetector.detect(
            historyRates: [-1, 0, 1, 0, -1, 1],
            historyBeatErrors: [0.3, 0.3, 0.3, 0.3, 0.3, 0.3],
            latestRate: -90,
            latestBeatError: 0.3
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.reason, .suspectShock)
        XCTAssertLessThan(result?.deviationSigma ?? 0, 0)
    }

    // MARK: - beat error 급증 → 탈진기 의심

    func test_beat_error_spike() {
        // rate 는 정상, beat error 만 급증.
        let result = AnomalyDetector.detect(
            historyRates: [-1, 0, 1, 0, -1, 1],
            historyBeatErrors: [0.2, 0.25, 0.2, 0.22, 0.2, 0.24],
            latestRate: 1,
            latestBeatError: 3.0
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.reason, .suspectBeatErrorSpike)
        XCTAssertGreaterThan(result?.deviationSigma ?? 0, 0)
    }

    func test_beat_error_decrease_not_flagged() {
        // beat error 가 줄어듦(개선) → 이상 아님.
        let result = AnomalyDetector.detect(
            historyRates: [-1, 0, 1, 0, -1, 1],
            historyBeatErrors: [2.0, 2.1, 1.9, 2.0, 2.1, 1.9],
            latestRate: 1,
            latestBeatError: 0.2
        )
        XCTAssertNil(result)
    }

    // MARK: - 더 강한 신호 축이 사유로 채택

    func test_rate_dominates_when_both_anomalous() {
        // rate 가 beat error 보다 훨씬 강한 σ 편차 → magnetization 채택.
        let result = AnomalyDetector.detect(
            historyRates: [-1, 0, 1, 0, -1, 1],
            historyBeatErrors: [0.2, 0.25, 0.2, 0.22, 0.2, 0.24],
            latestRate: 200,
            latestBeatError: 2.0
        )
        XCTAssertEqual(result?.reason, .suspectMagnetization)
    }

    // MARK: - 임계 파라미터 경계

    func test_higher_threshold_suppresses_borderline() {
        // 기본 임계로는 잡히지만 매우 높은 임계로는 통과.
        let rates: [Double] = [-2, 0, 2, 0, -2, 2]
        let be: [Double] = [0.3, 0.3, 0.3, 0.3, 0.3, 0.3]
        let flagged = AnomalyDetector.detect(historyRates: rates, historyBeatErrors: be,
                                             latestRate: 30, latestBeatError: 0.3,
                                             sigmaThreshold: 3.5)
        XCTAssertNotNil(flagged)
        let suppressed = AnomalyDetector.detect(historyRates: rates, historyBeatErrors: be,
                                                latestRate: 30, latestBeatError: 0.3,
                                                sigmaThreshold: 100)
        XCTAssertNil(suppressed)
    }
}
