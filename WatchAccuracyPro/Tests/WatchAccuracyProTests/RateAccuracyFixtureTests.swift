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

    func test_36000bph_highBeat_recoversOnRate() throws {
        // Zenith El Primero 등 36000 BPH(IOI 100ms). 감사 P1: 옛 refractory(100ms)가 IOI 와 같아
        //   onset 누락 위험 → adaptiveRefractoryMs(80ms) 적용 후 정상 lock·rate 복원·onset 확보 가드.
        let r = try measure(actualBph: 36_000, nominalBph: 36_000)
        print("🎯 36000: bph=\(r.bph) rate=\(String(format: "%.2f", r.rateSecondsPerDay)) beats=\(r.beatCount)")
        XCTAssertEqual(r.bph, 36_000, "고진동 BPH lock")
        XCTAssertEqual(r.rateSecondsPerDay, 0, accuracy: 10, "on-rate 합성은 ≈0 s/d")
        // 36000 BPH × 24s = 240 beats. refractory 로 onset 이 반토막 나면 안 됨.
        XCTAssertGreaterThan(r.beatCount, 120, "고진동에서 refractory 가 onset 을 과도히 솎으면 안 됨")
    }

    // MARK: - 진동수 오입력 복구 (auto-correct)

    /// 사용자 보고: "진동수를 잘못 입력했을 때 아예 측정이 안 됨".
    /// 원인: bphExplicit 일 때 BPH 후보가 입력값 ±20% 로 하드 락 → 실제 신호가 창 밖이면 lock 실패 → nil.
    /// 수정: hint 창 lock 실패 시 전대역 자동감지(무힌트)로 폴백 + 등록값과 다른 패밀리(>12%)면
    ///       nominalBph 를 감지값으로 보정 → 측정 성립 + mismatch 경고.
    /// 28800 시계를 21600(−25%, 창 밖)으로 잘못 등록해도 28800 패밀리로 lock·rate 복원해야 한다.
    func test_wrongBph_recoversViaAutoDetect() throws {
        let signal = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 24)
        let source = SyntheticAudioSource(signal: signal)
        let pipeline = DSPPipeline(
            source: source, nominalBph: 21_600,   // 사용자가 진동수를 틀리게 등록
            liftAngleDegrees: 52, escapement: .swissLever, reliabilityLabel: .high
        )
        try pipeline.start()
        let r = try XCTUnwrap(pipeline.stop(), "진동수 오입력(21600)인데도 측정이 nil 이면 안 됨 — 자동감지 복구 실패")
        print("🎯 wrongBph: bph=\(r.bph) rate=\(String(format: "%.2f", r.rateSecondsPerDay)) suggest=\(pipeline.bphMismatchSuggested ?? -1)")
        XCTAssertEqual(r.bph, 28_800, "틀린 21600 대신 실제 28800 패밀리로 자동 lock")
        XCTAssertEqual(r.rateSecondsPerDay, 0, accuracy: 12, "보정 후 on-rate 합성은 ≈0 s/d (틀린 nominal 로 계산하면 안 됨)")
        XCTAssertEqual(pipeline.bphMismatchSuggested, 28_800, "등록 BPH 와 불일치 — 감지값(28800) 제안")
    }

    /// 회귀 가드: 올바른 BPH 등록은 자동보정이 절대 끼어들지 않아야(mismatch nil, 진값 그대로).
    func test_correctBph_noFalseAutoCorrect() throws {
        let r = try measure(actualBph: 28_800, nominalBph: 28_800)
        XCTAssertEqual(r.bph, 28_800)
        XCTAssertEqual(r.rateSecondsPerDay, 0, accuracy: 10)
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

/// Round 176 (감사 P1) 회귀 가드 — ±s/d 불확도의 N 은 **실제 OLS fit beat 수**여야 한다.
/// 버그: 이전엔 N=beatCount(전체 onset)를 써서 fit 이 부분집합(예: 240 중 60)일 때
///   σ ∝ N^-1.5 이라 (240/60)^1.5 = 8× 과소평가 → ± 를 과신(좁게) 표시했다.
/// 표시(MeasurementResultView)와 persist 게이트(MeasurementViewModel)가
///   이제 동일한 순수 helper 를 공유하므로 양쪽 모두를 이 한 곳에서 가드한다.
final class RateFitUncertaintyTests: XCTestCase {

    private let rms = 40e-6          // 40μs residual
    private let bph = 28_800

    func test_uses_fitBeatCount_when_present_not_total_beatCount() throws {
        // fit=60(실제 OLS 잔차 수) vs 옛 동작(N=beatCount=240)
        let corrected = try XCTUnwrap(MeasurementResult.rateFitUncertaintySD(
            residualRMSSeconds: rms, fitBeatCount: 60, beatCount: 240, bph: bph))
        let naiveOld = try XCTUnwrap(MeasurementResult.rateFitUncertaintySD(
            residualRMSSeconds: rms, fitBeatCount: nil, beatCount: 240, bph: bph))   // 폴백 N=240
        // 과신 차단: fit beat 수가 적으면 ± 는 더 넓어져야(커져야) 한다.
        XCTAssertGreaterThan(corrected, naiveOld, "fit beat 수가 적으면 불확도는 더 커야(과신 방지)")
        // σ ∝ N^-1.5 → 비율 = (240/60)^1.5 = 8.0
        XCTAssertEqual(corrected / naiveOld, pow(240.0 / 60.0, 1.5), accuracy: 1e-9,
                       "비율은 (N_total/N_fit)^1.5 여야")
    }

    func test_fallback_to_beatCount_when_fitCount_nil_preserves_legacy() throws {
        let fallback = try XCTUnwrap(MeasurementResult.rateFitUncertaintySD(
            residualRMSSeconds: rms, fitBeatCount: nil, beatCount: 200, bph: bph))
        let explicit = try XCTUnwrap(MeasurementResult.rateFitUncertaintySD(
            residualRMSSeconds: rms, fitBeatCount: 200, beatCount: 999, bph: bph))
        XCTAssertEqual(fallback, explicit, accuracy: 1e-12,
                       "fitCount nil 이면 beatCount 로 폴백 — legacy 경로 보존")
    }

    func test_nil_when_inputs_insufficient() {
        XCTAssertNil(MeasurementResult.rateFitUncertaintySD(
            residualRMSSeconds: nil, fitBeatCount: 100, beatCount: 200, bph: bph), "rms nil → nil")
        XCTAssertNil(MeasurementResult.rateFitUncertaintySD(
            residualRMSSeconds: rms, fitBeatCount: 1, beatCount: 1, bph: bph), "N≤1 → nil")
        XCTAssertNil(MeasurementResult.rateFitUncertaintySD(
            residualRMSSeconds: rms, fitBeatCount: 100, beatCount: 200, bph: 0), "bph 0 → nil")
    }

    func test_concrete_magnitude() throws {
        // σ_slope = rms·√12 / N^1.5;  ±s/d = σ_slope / (3600/bph) · 86400
        let n = 240.0
        let expected = (rms * 12.0.squareRoot() / pow(n, 1.5)) / (3600.0 / Double(bph)) * 86400.0
        let got = try XCTUnwrap(MeasurementResult.rateFitUncertaintySD(
            residualRMSSeconds: rms, fitBeatCount: 240, beatCount: 240, bph: bph))
        XCTAssertEqual(got, expected, accuracy: 1e-9)
    }

    /// 인스턴스 computed 가 static 과 동일 — 표시·게이트 단일 소스 보장.
    func test_instance_property_matches_static() throws {
        var r = MeasurementResult(bph: bph, rateSecondsPerDay: 0, beatErrorMs: 0,
                                  amplitudeDegrees: nil, confidenceScore: 80,
                                  durationSeconds: 30, snrDB: 20, beatCount: 240,
                                  reliabilityNote: nil)
        r.residualRMSSeconds = rms
        r.rateFitBeatCount = 60
        let viaInstance = try XCTUnwrap(r.rateFitUncertaintySD)
        let viaStatic = try XCTUnwrap(MeasurementResult.rateFitUncertaintySD(
            residualRMSSeconds: rms, fitBeatCount: 60, beatCount: 240, bph: bph))
        XCTAssertEqual(viaInstance, viaStatic, accuracy: 1e-12)
    }
}
