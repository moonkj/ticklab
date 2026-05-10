import XCTest
@testable import WatchAccuracyPro

final class RateCalculatorTests: XCTestCase {
    func test_zero_difference_returns_zero() {
        let result = RateCalculator.secondsPerDay(measuredBph: 28_800, nominalBph: 28_800)
        XCTAssertEqual(result, 0, accuracy: 0.001)
    }

    func test_positive_drift_returns_positive_seconds() {
        // 28800에서 +0.05% 빠르면 +43.2초/일
        let result = RateCalculator.secondsPerDay(measuredBph: 28_814.4, nominalBph: 28_800)
        XCTAssertEqual(result, 43.2, accuracy: 0.5)
    }

    func test_negative_drift_returns_negative_seconds() {
        let result = RateCalculator.secondsPerDay(measuredBph: 28_785.6, nominalBph: 28_800)
        XCTAssertEqual(result, -43.2, accuracy: 0.5)
    }

    func test_secondsPerDay_from_beats_synthesizes_correct_rate() {
        // 28800 BPH = 8 beats/sec. 5초 동안 정확히 측정된 41 events (40 intervals).
        let beats: [BeatEvent] = (0..<41).map {
            BeatEvent(timestampSeconds: Double($0) * 0.125, type: $0.isMultiple(of: 2) ? .tic : .toc, energy: 1)
        }
        let result = RateCalculator.secondsPerDay(beats: beats, nominalBph: 28_800)
        XCTAssertEqual(result ?? -999, 0, accuracy: 0.5)
    }

    func test_too_few_beats_returns_nil() {
        let beats = [BeatEvent(timestampSeconds: 0, type: .tic, energy: 1)]
        XCTAssertNil(RateCalculator.secondsPerDay(beats: beats, nominalBph: 28_800))
    }
}
