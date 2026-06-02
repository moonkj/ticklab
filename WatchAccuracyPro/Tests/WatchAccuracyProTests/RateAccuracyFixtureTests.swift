import XCTest
@testable import WatchAccuracyPro

/// Round 171 (전원 재감사 후 rate 근본수정) 회귀 가드.
/// analyzeSimplified 가 48kHz refined onset 의 OLS slope 로 합성 신호의 **진짜 rate** 를
/// 복원하는지 검증한다. 합성은 깨끗한 임펄스 트레인이라 진값을 정확히 안다:
///   actualBph 28814 → +42.0 s/d, 28786 → -42.0 s/d, 28800 → 0 s/d.
///
/// 배경: 이전 200Hz autocorrelation rawBph 경로는 동일 fixture 에서
///   on-rate ≈ -1.2 / fast(+42) ≈ 16.2 / slow(-42) ≈ -9.4 로 진값의 절반 이하만 복원
///   (lag=25 샘플의 coarse-grid 압축 bias). OLS 경로는 진값 근처를 회복해야 한다.
@MainActor
final class RateAccuracyFixtureTests: XCTestCase {

    private func measure(actualBph: Int, nominalBph: Int, duration: Double = 24) throws -> MeasurementResult {
        let signal = SyntheticSignal.ticTocImpulseTrain(bph: actualBph, duration: duration)
        let source = SyntheticAudioSource(signal: signal)
        let pipeline = DSPPipeline(
            source: source, nominalBph: nominalBph,
            liftAngleDegrees: 52, escapement: .swissLever, reliabilityLabel: .high
        )
        try pipeline.start()
        return try XCTUnwrap(pipeline.stop(), "분석 실패(lock 못함) actualBph=\(actualBph)")
    }

    func test_onRate_isNearZero() throws {
        let r = try measure(actualBph: 28_800, nominalBph: 28_800)
        print("🎯 on-rate: bph=\(r.bph) rate=\(String(format: "%.2f", r.rateSecondsPerDay)) s/d")
        XCTAssertEqual(r.bph, 28_800, "BPH 패밀리 lock")
        XCTAssertEqual(r.rateSecondsPerDay, 0, accuracy: 10, "on-rate 합성은 ≈0 s/d")
    }

    func test_fast_recoversPositiveRate() throws {
        // actualBph 28814 → 진짜 +42 s/d.
        let r = try measure(actualBph: 28_814, nominalBph: 28_800)
        print("🎯 fast: bph=\(r.bph) rate=\(String(format: "%.2f", r.rateSecondsPerDay)) s/d (진값 +42)")
        XCTAssertEqual(r.bph, 28_800, "BPH 패밀리 lock")
        // 회귀 가드: 진값 +42 의 명확한 +방향 복원 (이전 autocorr 경로의 +16 압축 bias 아님).
        XCTAssertGreaterThan(r.rateSecondsPerDay, 28, "fast 진값 +42 의 대부분 복원해야 (autocorr 16 bias 탈출)")
        XCTAssertEqual(r.rateSecondsPerDay, 42, accuracy: 8, "fast 진값 +42 근처")
    }

    func test_slow_recoversNegativeRate() throws {
        // actualBph 28786 → 진짜 -42 s/d.
        let r = try measure(actualBph: 28_786, nominalBph: 28_800)
        print("🎯 slow: bph=\(r.bph) rate=\(String(format: "%.2f", r.rateSecondsPerDay)) s/d (진값 -42)")
        XCTAssertEqual(r.bph, 28_800, "BPH 패밀리 lock")
        XCTAssertLessThan(r.rateSecondsPerDay, -28, "slow 진값 -42 의 대부분 복원해야 (autocorr -9 bias 탈출)")
        XCTAssertEqual(r.rateSecondsPerDay, -42, accuracy: 8, "slow 진값 -42 근처")
    }

    // MARK: - Phase B: 신뢰 게이트 (cross-window 일관성)

    func test_consistentMeasurement_smallSpread_gradeA() throws {
        // 32s 일관 on-rate → 3 sub-window OLS rate 거의 동일 → spread 작음 → grade A.
        let r = try measure(actualBph: 28_800, nominalBph: 28_800, duration: 32)
        let spread = try XCTUnwrap(r.crossWindowRateDelta, "Phase B: cross-window 게이트가 delta 를 채워야(휴면 아님)")
        print("🔁 clean: spread=\(String(format: "%.2f", spread)) grade=\(r.reliabilityGrade?.rawValue ?? "?")")
        XCTAssertLessThan(spread, 10, "일관된 합성 신호는 sub-window 간 spread 작아야")
        XCTAssertEqual(r.reliabilityGrade, .a, "일관 + 고신뢰 → grade A")
    }

    func test_inconsistentMeasurement_largeSpread_downgrades() throws {
        // 전반 16s 28800(≈0) + 후반 16s 28760(≈-120) → 구간 rate 크게 다름 → spread 큼 → A 아님.
        let signal = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 16)
            + SyntheticSignal.ticTocImpulseTrain(bph: 28_760, duration: 16)
        let source = SyntheticAudioSource(signal: signal)
        let pipeline = DSPPipeline(
            source: source, nominalBph: 28_800,
            liftAngleDegrees: 52, escapement: .swissLever, reliabilityLabel: .high
        )
        try pipeline.start()
        let r = try XCTUnwrap(pipeline.stop(), "분석 실패")
        let spread = try XCTUnwrap(r.crossWindowRateDelta, "cross-window delta 채워져야")
        print("🔁 inconsistent: spread=\(String(format: "%.1f", spread)) grade=\(r.reliabilityGrade?.rawValue ?? "?")")
        XCTAssertGreaterThan(spread, 30, "구간별 rate 가 다르면 spread 커야")
        XCTAssertNotEqual(r.reliabilityGrade, .a, "불안정 측정은 grade A 로 과신하면 안 됨")
    }

    // MARK: - C1: robust 집계 (오염 구간 배제)

    func test_inconsistentWindows_areFlaggedNotCorrected() throws {
        // Round 171 (사용자 실측 진단 후 정책): 구간별 rate 가 흩어지면 headline 을 median 으로 교체하지 않고
        //   (10s 윈도우 노이즈가 더 크다는 실측) **플래그**(큰 spread → grade 강등)만 한다.
        // 깨끗(28800) 10s + 오염(28760,≈-120) 10s + 깨끗(28800) 10s → 구간 spread 큼.
        let signal = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 10)
            + SyntheticSignal.ticTocImpulseTrain(bph: 28_760, duration: 10)
            + SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 10)
        let source = SyntheticAudioSource(signal: signal)
        let pipeline = DSPPipeline(
            source: source, nominalBph: 28_800,
            liftAngleDegrees: 52, escapement: .swissLever, reliabilityLabel: .high
        )
        try pipeline.start()
        let r = try XCTUnwrap(pipeline.stop(), "분석 실패")
        let spread = try XCTUnwrap(r.crossWindowRateDelta, "cross-window delta 채워져야")
        print("🚩 flag: rate=\(String(format: "%.1f", r.rateSecondsPerDay)) spread=\(String(format: "%.1f", spread)) grade=\(r.reliabilityGrade?.rawValue ?? "?")")
        // Round 172: 재현성 신호 = tg σ×2 (옛 win-spread 아님). 불일치 구간이면 tg cycle 들이 흩어져 커진다.
        XCTAssertGreaterThan(spread, 20, "구간별 rate 가 다르면 재현성 신호(tg σ)가 커야")
        XCTAssertNotEqual(r.reliabilityGrade, .a, "불안정 구간 → grade A 로 과신하면 안 됨")
    }
}
