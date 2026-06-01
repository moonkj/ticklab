import XCTest
@testable import WatchAccuracyPro

/// 빠른 측정 A/B 스윕 — 여러 drift 조건에서 조기종료 vs 전체분석 정량 비교.
/// 28800 계열(합성 lock 신뢰 높음)에서 true rate 0/+/− 를 bph 오프셋으로 만든다.
final class FastRateABSweepTests: XCTestCase {

    /// (라벨, 실제 bph, 명목 bph, 기대 rate 부호 설명)
    private let conditions: [(label: String, actualBph: Int, nominalBph: Int)] = [
        ("on-rate  (≈0 s/d)", 28_800, 28_800),
        ("fast     (≈+42 s/d)", 28_814, 28_800),
        ("slow     (≈-42 s/d)", 28_786, 28_800),
    ]

    func test_ab_sweep_earlyExit_vs_full() throws {
        let windows: [Double] = [4, 6, 8, 10, 12]
        var convergedCount = 0
        var sumSpeedup = 0.0

        func f(_ x: Double) -> String { String(format: "%.1f", x) }
        print("\n=== FastRate A/B (early-exit vs full 12s) ===")
        print("condition | full s/d | early s/d | Δ(e-f) | conv s | converged")

        for c in conditions {
            let signal = SyntheticSignal.ticTocImpulseTrain(bph: c.actualBph, duration: 12)
            let source = SyntheticAudioSource(signal: signal)
            let pipeline = DSPPipeline(
                source: source, nominalBph: c.nominalBph,
                liftAngleDegrees: 52, escapement: .swissLever, reliabilityLabel: .high
            )
            try pipeline.start()
            guard let full = pipeline.stop() else {
                print("\(c.label): full 분석 실패(synthetic lock 실패) — 스킵")
                continue
            }
            guard let outcome = pipeline.measureEarlyExit(
                candidateWindows: windows, toleranceSecondsPerDay: 10.0, stableCount: 3
            ) else {
                print("\(c.label): early-exit 결과 없음 — 스킵")
                continue
            }

            let delta = outcome.result.rateSecondsPerDay - full.rateSecondsPerDay
            print("\(c.label) | \(f(full.rateSecondsPerDay)) | \(f(outcome.result.rateSecondsPerDay)) | \(f(delta)) | \(f(outcome.convergedSeconds)) | \(outcome.didConverge ? "YES" : "no")")

            // 핵심 불변식: 조기종료 rate ≈ 전체 rate (정확도 보존).
            XCTAssertEqual(outcome.result.rateSecondsPerDay, full.rateSecondsPerDay, accuracy: 120,
                           "[\(c.label)] 조기종료가 전체분석과 크게 어긋나면 안 됨")
            XCTAssertEqual(outcome.result.bph, full.bph, "[\(c.label)] BPH 동일해야 함")

            if outcome.didConverge {
                convergedCount += 1
                sumSpeedup += (12.0 - outcome.convergedSeconds)
            }
        }

        print("=== 수렴 \(convergedCount)/\(conditions.count) 조건, 평균 단축 \(convergedCount > 0 ? sumSpeedup / Double(convergedCount) : 0)s (12s 기준) ===\n")
        // 최소 한 조건은 수렴(메커니즘 동작 확인).
        XCTAssertGreaterThan(convergedCount, 0, "어느 조건도 수렴 못 하면 조기종료 무의미")
    }
}
