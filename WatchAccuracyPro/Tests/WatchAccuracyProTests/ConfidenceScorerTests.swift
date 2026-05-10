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
        // SNR 20 + duration 15 + BPH 25*0.8=20 + beat error 20*(1-0.25)=15 = 70
        XCTAssertEqual(score, 70)
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
        XCTAssertEqual(score, 80, "beat error 2ms 이상이면 separation 점수는 0")
    }
}
