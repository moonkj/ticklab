import XCTest
@testable import WatchAccuracyPro

final class BeatErrorCalculatorTests: XCTestCase {
    func test_symmetric_beats_have_zero_error() {
        let interval = 0.125
        let beats: [BeatEvent] = (0..<20).map {
            BeatEvent(timestampSeconds: Double($0) * interval, type: $0.isMultiple(of: 2) ? .tic : .toc, energy: 1)
        }
        let err = BeatErrorCalculator.beatErrorMs(beats: beats)
        XCTAssertEqual(err ?? -999, 0, accuracy: 0.001)
    }

    func test_asymmetric_beats_match_expected_error() {
        // tic→toc 130ms, toc→tic 120ms → 평균 차이 10ms
        var beats: [BeatEvent] = []
        var t: Double = 0
        for i in 0..<20 {
            beats.append(BeatEvent(timestampSeconds: t, type: i.isMultiple(of: 2) ? .tic : .toc, energy: 1))
            t += i.isMultiple(of: 2) ? 0.130 : 0.120
        }
        let err = BeatErrorCalculator.beatErrorMs(beats: beats)
        XCTAssertEqual(err ?? -999, 10, accuracy: 0.5)
    }

    func test_too_few_beats_returns_nil() {
        let beats = (0..<3).map { BeatEvent(timestampSeconds: Double($0) * 0.125, type: .tic, energy: 1) }
        XCTAssertNil(BeatErrorCalculator.beatErrorMs(beats: beats))
    }
}
