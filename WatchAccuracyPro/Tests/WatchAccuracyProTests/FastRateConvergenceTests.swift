import XCTest
@testable import WatchAccuracyPro

/// 빠른 측정 프로토타입 — 수렴 판정(순수) + fixture A/B(조기종료 vs 전체분석).
final class FastRateConvergenceTests: XCTestCase {

    // MARK: - 순수 수렴 판정

    func test_stable_sequence_converges_at_third_window() {
        let rates: [(seconds: Double, rate: Double)] = [
            (4, 2.0), (6, 2.5), (8, 1.8), (10, 30.0), (12, 2.0)
        ]
        // tol 2.0, stableCount 3 → 인덱스 0,1,2 (2.0/2.5/1.8 spread 0.7) 가 첫 안정 → 8s 에 조기 수렴.
        let conv = FastRateConvergence.firstStableWindow(rates: rates, toleranceSecondsPerDay: 2.0, stableCount: 3)
        XCTAssertEqual(conv?.seconds, 8.0)
        XCTAssertEqual(conv?.index, 2)
    }

    func test_oscillating_sequence_does_not_converge() {
        let rates: [(seconds: Double, rate: Double)] = [
            (4, 0), (6, 50), (8, 0), (10, 50), (12, 0)
        ]
        XCTAssertNil(FastRateConvergence.firstStableWindow(rates: rates, toleranceSecondsPerDay: 2.0, stableCount: 3))
    }

    func test_too_few_samples_returns_nil() {
        let rates: [(seconds: Double, rate: Double)] = [(4, 1.0), (6, 1.0)]
        XCTAssertNil(FastRateConvergence.firstStableWindow(rates: rates, toleranceSecondsPerDay: 2.0, stableCount: 3))
    }

    func test_immediate_stability_returns_earliest_possible() {
        let rates: [(seconds: Double, rate: Double)] = [(4, 5.0), (6, 5.1), (8, 4.9)]
        let conv = FastRateConvergence.firstStableWindow(rates: rates, toleranceSecondsPerDay: 1.0, stableCount: 3)
        XCTAssertEqual(conv?.seconds, 8.0)   // 3개째에서 첫 판정
    }

    func test_tolerance_boundary() {
        let rates: [(seconds: Double, rate: Double)] = [(4, 0), (6, 2), (8, 0)]  // spread 2.0
        XCTAssertNotNil(FastRateConvergence.firstStableWindow(rates: rates, toleranceSecondsPerDay: 2.0, stableCount: 3))
        XCTAssertNil(FastRateConvergence.firstStableWindow(rates: rates, toleranceSecondsPerDay: 1.9, stableCount: 3))
    }

    func test_stableCount_one_converges_immediately() {
        let rates: [(seconds: Double, rate: Double)] = [(4, 99.0)]
        let conv = FastRateConvergence.firstStableWindow(rates: rates, toleranceSecondsPerDay: 2.0, stableCount: 1)
        XCTAssertEqual(conv?.seconds, 4.0)
    }

    // MARK: - Fixture A/B: 조기종료가 전체분석과 동일 rate 를 더 빨리

    func test_earlyExit_matches_fullWindow_rate_but_sooner_28800() throws {
        // 12초 합성 신호(28800 BPH, drift 0). 윈도우 키우며 수렴 탐색.
        let signal = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 12)
        let source = SyntheticAudioSource(signal: signal)
        let pipeline = DSPPipeline(
            source: source, nominalBph: 28_800,
            liftAngleDegrees: 52, escapement: .swissLever, reliabilityLabel: .high
        )
        try pipeline.start()
        // stop() = 1Hz 백그라운드 분석기 취소 + 전체 결과(기준선). 버퍼는 유지되어
        // 이후 analyze 스윕이 경합 없이 동작.
        let full = try XCTUnwrap(pipeline.stop(), "전체 윈도우 분석 실패")

        // 조기종료 — 윈도우 [4,6,8,10,12] 스윕.
        let outcome = try XCTUnwrap(
            pipeline.measureEarlyExit(candidateWindows: [4, 6, 8, 10, 12],
                                      toleranceSecondsPerDay: 10.0, stableCount: 3),
            "조기종료 결과 없음"
        )

        XCTAssertEqual(outcome.result.bph, 28_800, "BPH 동일")
        // 핵심 1 — 정확도 보존: 조기종료 rate ≈ 전체 rate.
        XCTAssertEqual(outcome.result.rateSecondsPerDay, full.rateSecondsPerDay, accuracy: 100,
                       "조기종료 rate 가 전체분석과 크게 다르면 안 됨")
        // 핵심 2 — 전체 rate 는 진값(0) 근처(기존 synthetic 허용 ±200).
        XCTAssertEqual(full.rateSecondsPerDay, 0, accuracy: 200)
        // 핵심 3 — 수렴 시 전체(12s)보다 이른 시점.
        if outcome.didConverge {
            XCTAssertLessThanOrEqual(outcome.convergedSeconds, 12)
        }
    }
}
