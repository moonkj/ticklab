import XCTest
@testable import WatchAccuracyPro

final class ConfidenceScorerTests: XCTestCase {
    func test_perfect_inputs_score_100() {
        let score = ConfidenceScorer.score(.init(
            snrDB: 35,
            durationSeconds: 120,
            bphAutocorrelationConfidence: 1.0,
            beatCount: 1000,
            beatErrorMs: 0
        ))
        XCTAssertEqual(score, 100)
    }

    func test_terrible_inputs_score_zero() {
        let score = ConfidenceScorer.score(.init(
            snrDB: 5,
            durationSeconds: 5,
            bphAutocorrelationConfidence: 0,
            beatCount: 0,
            beatErrorMs: nil
        ))
        XCTAssertEqual(score, 0)
    }

    func test_mid_inputs_partial_score() {
        let score = ConfidenceScorer.score(.init(
            snrDB: 25,
            durationSeconds: 60,
            bphAutocorrelationConfidence: 0.8,
            beatCount: 500,
            beatErrorMs: 0.5
        ))
        // Round 110 가중치: SNR 25dB(22dB상한) = 20점(만점).
        // duration 60s = 17점. BPH 30*0.8 = 24점. beat error 25*(1-0.25) = 19점.
        // 총 = 20+17+24+19 = 80점.
        XCTAssertEqual(score, 80)
    }

    func test_realistic_watch_signal_scores_above_50() {
        // 실 기계식 시계 보통 시나리오: SNR 18dB, 30s, BPH conf 0.7, beat error 0.6ms
        // 신뢰도가 적어도 50 이상이라야 사용자에게 의미 있다.
        let score = ConfidenceScorer.score(.init(
            snrDB: 18,
            durationSeconds: 30,
            bphAutocorrelationConfidence: 0.7,
            beatCount: 240,
            beatErrorMs: 0.6
        ))
        XCTAssertGreaterThan(score, 50, "실 시계 평균 신호에서 신뢰도는 50점 이상 — got \(score)")
    }

    func test_score_never_exceeds_100() {
        let score = ConfidenceScorer.score(.init(
            snrDB: 40,
            durationSeconds: 300,
            bphAutocorrelationConfidence: 1.0,
            beatCount: 9999,
            beatErrorMs: 0
        ))
        XCTAssertLessThanOrEqual(score, 100)
    }

    func test_high_beat_error_drops_separation_component() {
        let score = ConfidenceScorer.score(.init(
            snrDB: 35,
            durationSeconds: 120,
            bphAutocorrelationConfidence: 1.0,
            beatCount: 1000,
            beatErrorMs: 5  // 매우 큰 beat error
        ))
        // SNR≥22→20 + duration≥120→25 + BPH conf 1.0→30 + beatError≥2ms→0 = 75.
        XCTAssertEqual(score, 75, "beat error 2ms 이상이면 separation 점수는 0 → 총 75점")
    }
}
