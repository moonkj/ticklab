import XCTest
@testable import WatchAccuracyPro

/// `ReliabilityGrade.from(...)` 순수 임계 로직 회귀 보호.
/// Round 152/154/158 의 confidence + cross-window delta + |rate| penalty 매핑을 잠근다.
/// 네트워크/시스템 의존 없음 — 결정론적 산술만.
final class ReliabilityGradeTests: XCTestCase {

    // MARK: - 기본 confidence → grade 경계 (penalty 0)

    func test_high_confidence_no_penalty_is_a() {
        // confidence 75 이상, delta nil, rate 0 → penalty 0 → 75 → .a
        XCTAssertEqual(ReliabilityGrade.from(confidence: 75, crossWindowDelta: nil), .a)
        XCTAssertEqual(ReliabilityGrade.from(confidence: 100, crossWindowDelta: nil), .a)
    }

    func test_mid_confidence_is_b() {
        // 55..<75 → .b
        XCTAssertEqual(ReliabilityGrade.from(confidence: 55, crossWindowDelta: nil), .b)
        XCTAssertEqual(ReliabilityGrade.from(confidence: 74, crossWindowDelta: nil), .b)
    }

    func test_low_confidence_is_c() {
        // 35..<55 → .c
        XCTAssertEqual(ReliabilityGrade.from(confidence: 35, crossWindowDelta: nil), .c)
        XCTAssertEqual(ReliabilityGrade.from(confidence: 54, crossWindowDelta: nil), .c)
    }

    func test_very_low_confidence_is_f() {
        // < 35 → .f
        XCTAssertEqual(ReliabilityGrade.from(confidence: 34, crossWindowDelta: nil), .f)
        XCTAssertEqual(ReliabilityGrade.from(confidence: 0, crossWindowDelta: nil), .f)
    }

    // MARK: - cross-window delta penalty

    func test_small_delta_below_threshold_no_penalty() {
        // Round 173: delta 5 이하 → windowPenalty 0. confidence 75 유지 → .a
        XCTAssertEqual(ReliabilityGrade.from(confidence: 75, crossWindowDelta: 5), .a)
        XCTAssertEqual(ReliabilityGrade.from(confidence: 75, crossWindowDelta: 4), .a)
    }

    func test_delta_penalty_drops_grade() {
        // Round 173 강화: (d-5)*3.0, cap 60.
        // delta 30 → (30-5)*3=75→cap60. 75 - 60 = 15 → .f
        XCTAssertEqual(ReliabilityGrade.from(confidence: 75, crossWindowDelta: 30), .f)
        // delta 8(σ4) → (8-5)*3=9. 90-9=81 → .a 유지 (괜찮은 측정).
        XCTAssertEqual(ReliabilityGrade.from(confidence: 90, crossWindowDelta: 8), .a)
        // delta 14.8(σ7.4) → (14.8-5)*3=29.4→29. 90-29=61 → .b (confidence 높을 때).
        XCTAssertEqual(ReliabilityGrade.from(confidence: 90, crossWindowDelta: 14.8), .b)
    }

    /// Round 173 (감사 P0): σ7.4 garbage 는 TG 락 실패로 confidence 도 함께 떨어져(파이프라인 −30)
    /// 두 레이어 결합 시 C/F 로 강등돼야 한다. 여기선 grade 레이어 단독 검증.
    func test_high_sigma_with_lowered_confidence_downgrades() {
        // σ7.4(delta 14.8) + TG실패로 낮아진 confidence 65 → 65-29=36 → .c
        XCTAssertEqual(ReliabilityGrade.from(confidence: 65, crossWindowDelta: 14.8), .c)
        // 클린비율까지 나빠 confidence 45 → 45-29=16 → .f
        XCTAssertEqual(ReliabilityGrade.from(confidence: 45, crossWindowDelta: 14.8), .f)
    }

    func test_delta_penalty_is_capped() {
        // Round 173: windowPenalty cap 60. 최고 confidence 100 - 60 = 40 → 최선 .c.
        XCTAssertEqual(ReliabilityGrade.from(confidence: 100, crossWindowDelta: 1000), .c)
        // 90 - 60 = 30 → .f
        XCTAssertEqual(ReliabilityGrade.from(confidence: 90, crossWindowDelta: 1000), .f)
        // 55 - 60 < 0 → .f
        XCTAssertEqual(ReliabilityGrade.from(confidence: 55, crossWindowDelta: 1000), .f)
    }

    // MARK: - |rate| penalty (Round 158)

    func test_rate_within_30_no_penalty() {
        // |rate| <= 30 → ratePenalty 0.
        XCTAssertEqual(
            ReliabilityGrade.from(confidence: 80, crossWindowDelta: nil, rateSecondsPerDay: 30),
            .a
        )
        XCTAssertEqual(
            ReliabilityGrade.from(confidence: 80, crossWindowDelta: nil, rateSecondsPerDay: -30),
            .a
        )
    }

    func test_rate_30_to_60_linear_penalty() {
        // |rate| 50 → penalty = 50 - 30 = 20. 90 - 20 = 70 → .b
        XCTAssertEqual(
            ReliabilityGrade.from(confidence: 90, crossWindowDelta: nil, rateSecondsPerDay: 50),
            .b
        )
    }

    func test_rate_60_to_120_half_slope_penalty() {
        // |rate| 100 → penalty = 30 + (100-60)/2 = 30 + 20 = 50. 90 - 50 = 40 → .c
        XCTAssertEqual(
            ReliabilityGrade.from(confidence: 90, crossWindowDelta: nil, rateSecondsPerDay: 100),
            .c
        )
    }

    func test_rate_above_120_always_f_grade() {
        // |rate| > 120 → penalty 60. confidence 100 - 60 = 40 → .c (penalty 자체로 40)
        XCTAssertEqual(
            ReliabilityGrade.from(confidence: 100, crossWindowDelta: nil, rateSecondsPerDay: 150),
            .c
        )
        // 사용자 보고 케이스 의도: 큰 rate 는 grade 를 낮춘다. confidence 보통이면 .f.
        XCTAssertEqual(
            ReliabilityGrade.from(confidence: 90, crossWindowDelta: nil, rateSecondsPerDay: 200),
            .f
        )
    }

    func test_negative_rate_uses_absolute_value() {
        // 부호 무관 — |rate| 기반.
        let pos = ReliabilityGrade.from(confidence: 90, crossWindowDelta: nil, rateSecondsPerDay: 100)
        let neg = ReliabilityGrade.from(confidence: 90, crossWindowDelta: nil, rateSecondsPerDay: -100)
        XCTAssertEqual(pos, neg)
    }

    // MARK: - 결합 penalty

    func test_window_and_rate_penalty_combine() {
        // Round 173: delta 35 → windowPenalty (35-5)*3=90→cap60.
        // rate 50 → ratePenalty 20. confidence 95 - 60 - 20 = 15 → .f
        XCTAssertEqual(
            ReliabilityGrade.from(confidence: 95, crossWindowDelta: 35, rateSecondsPerDay: 50),
            .f
        )
    }

    // MARK: - 2-인자 overload 는 rate 0 으로 위임

    func test_two_arg_overload_delegates_with_zero_rate() {
        // 같은 confidence/delta 면 3-인자(rate 0) 와 동일해야 한다.
        XCTAssertEqual(
            ReliabilityGrade.from(confidence: 60, crossWindowDelta: nil),
            ReliabilityGrade.from(confidence: 60, crossWindowDelta: nil, rateSecondsPerDay: 0)
        )
    }

    // MARK: - rawValue 안정성 (Codable 키 회귀)

    func test_raw_values_are_stable_lowercase() {
        XCTAssertEqual(ReliabilityGrade.a.rawValue, "a")
        XCTAssertEqual(ReliabilityGrade.b.rawValue, "b")
        XCTAssertEqual(ReliabilityGrade.c.rawValue, "c")
        XCTAssertEqual(ReliabilityGrade.f.rawValue, "f")
    }

    // MARK: - Round 173: confidence 보정 (DSPPipeline.adjustConfidence)

    func test_adjustConfidence_tgFail_penalizes() {
        // TG 락 실패 → −30. 클린비율 양호(1.0) → 추가 감점 없음.
        XCTAssertEqual(DSPPipeline.adjustConfidence(base: 90, tgLocked: false, cleanedBeats: 200, onsetCount: 200), 60, accuracy: 0.001)
    }

    func test_adjustConfidence_lowCleanRatio_penalizes() {
        // cleanRatio 0.45 (<0.5) → −20. TG 락 양호.
        XCTAssertEqual(DSPPipeline.adjustConfidence(base: 90, tgLocked: true, cleanedBeats: 90, onsetCount: 200), 70, accuracy: 0.001)
        // cleanRatio 0.6 (<0.7) → −10.
        XCTAssertEqual(DSPPipeline.adjustConfidence(base: 90, tgLocked: true, cleanedBeats: 120, onsetCount: 200), 80, accuracy: 0.001)
    }

    func test_adjustConfidence_garbage_combinesPenalties_floorsAtZero() {
        // σ7.4 garbage 전형: TG실패(−30) + cleanRatio 0.48(−20) → 90-50=40 (이후 grade 에서 추가 강등).
        XCTAssertEqual(DSPPipeline.adjustConfidence(base: 90, tgLocked: false, cleanedBeats: 96, onsetCount: 200), 40, accuracy: 0.001)
        // 음수 방지.
        XCTAssertEqual(DSPPipeline.adjustConfidence(base: 20, tgLocked: false, cleanedBeats: 10, onsetCount: 200), 0, accuracy: 0.001)
    }

    func test_adjustConfidence_clean_noPenalty() {
        XCTAssertEqual(DSPPipeline.adjustConfidence(base: 95, tgLocked: true, cleanedBeats: 230, onsetCount: 240), 95, accuracy: 0.001)
    }

    // MARK: - Round 174: IOI 정수배 필터 술어 (DSPPipeline.ioiIsIntegerMultiple)

    private let p0 = 0.125   // 28800 BPH nominal 주기

    func test_ioi_exact_multiples_pass() {
        for k in [1.0, 2.0, 3.0, 5.0] {
            XCTAssertTrue(DSPPipeline.ioiIsIntegerMultiple(p0 * k, nominalPeriod: p0, tolerance: 0.01, maxMultiple: 5),
                          "\(k)× 는 통과해야")
        }
    }

    func test_ioi_beyond_max_multiple_fails() {
        XCTAssertFalse(DSPPipeline.ioiIsIntegerMultiple(p0 * 6, nominalPeriod: p0, tolerance: 0.01, maxMultiple: 5))
    }

    func test_ioi_sub_period_fails() {
        // 0.5× → 정수배 아님 → 거부.
        XCTAssertFalse(DSPPipeline.ioiIsIntegerMultiple(p0 * 0.5, nominalPeriod: p0, tolerance: 0.01, maxMultiple: 5))
    }

    func test_ioi_within_tolerance_passes_outside_fails() {
        XCTAssertTrue(DSPPipeline.ioiIsIntegerMultiple(p0 * 1.005, nominalPeriod: p0, tolerance: 0.01, maxMultiple: 5))
        XCTAssertFalse(DSPPipeline.ioiIsIntegerMultiple(p0 * 1.02, nominalPeriod: p0, tolerance: 0.01, maxMultiple: 5))
    }

    func test_ioi_invalid_nominal_fails() {
        XCTAssertFalse(DSPPipeline.ioiIsIntegerMultiple(0.125, nominalPeriod: 0, tolerance: 0.01, maxMultiple: 5))
    }
}
