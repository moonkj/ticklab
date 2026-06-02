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
        // Round 171: delta 8 이하 → windowPenalty 0. confidence 75 유지 → .a
        XCTAssertEqual(ReliabilityGrade.from(confidence: 75, crossWindowDelta: 8), .a)
        XCTAssertEqual(ReliabilityGrade.from(confidence: 75, crossWindowDelta: 5), .a)
    }

    func test_delta_penalty_drops_grade() {
        // Round 171: delta 30 → penalty = (30-8)*1.0 = 22. 75 - 22 = 53 → .c
        XCTAssertEqual(ReliabilityGrade.from(confidence: 75, crossWindowDelta: 30), .c)
        // delta 20(±10) 은 A 유지: (20-8)=12, 90-12=78 → .a
        XCTAssertEqual(ReliabilityGrade.from(confidence: 90, crossWindowDelta: 20), .a)
        // delta 28(±14) 은 강등: (28-8)=20, 90-20=70 → .b
        XCTAssertEqual(ReliabilityGrade.from(confidence: 90, crossWindowDelta: 28), .b)
    }

    func test_delta_penalty_is_capped() {
        // Round 171: delta 매우 큼 → windowPenalty cap 50. 최고 confidence 100 - 50 = 50 → 최선 .c.
        XCTAssertEqual(ReliabilityGrade.from(confidence: 100, crossWindowDelta: 1000), .c)
        XCTAssertEqual(ReliabilityGrade.from(confidence: 90, crossWindowDelta: 1000), .c)
        // 55 - 50 = 5 → .f
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
        // Round 171: delta 35 → windowPenalty (35-8)*1.0 = 27.
        // rate 50 → ratePenalty 20. confidence 95 - 27 - 20 = 48 → .c
        XCTAssertEqual(
            ReliabilityGrade.from(confidence: 95, crossWindowDelta: 35, rateSecondsPerDay: 50),
            .c
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
}
