import XCTest
@testable import WatchAccuracyPro

final class BPHEstimatorTests: XCTestCase {
    func test_estimate_28800bph_within_half_percent() {
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 5, ticToTocDelayMs: 0)
        let envelope = makeEnvelope(raw)
        let estimate = BPHEstimator.estimate(envelope: envelope)
        XCTAssertNotNil(estimate)
        XCTAssertEqual(estimate?.bph, 28_800)
        if let raw = estimate?.rawBph {
            let error = abs(raw - 28_800) / 28_800
            XCTAssertLessThan(error, 0.005, "rawBph 가 ±0.5% 이내여야 한다 — got \(raw)")
        }
    }

    func test_estimate_21600bph_seiko_nh35() {
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 21_600, duration: 5)
        let envelope = makeEnvelope(raw)
        let estimate = BPHEstimator.estimate(envelope: envelope)
        XCTAssertEqual(estimate?.bph, 21_600)
    }

    func test_estimate_36000bph_high_beat() {
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 36_000, duration: 5)
        let envelope = makeEnvelope(raw)
        let estimate = BPHEstimator.estimate(envelope: envelope)
        XCTAssertEqual(estimate?.bph, 36_000)
    }

    func test_estimate_25200bph_omega_8800() {
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 25_200, duration: 5)
        let envelope = makeEnvelope(raw)
        let estimate = BPHEstimator.estimate(envelope: envelope)
        XCTAssertEqual(estimate?.bph, 25_200)
    }

    func test_estimate_short_signal_returns_nil() {
        let raw = [Float](repeating: 0, count: 100)
        let envelope = makeEnvelope(raw)
        let estimate = BPHEstimator.estimate(envelope: envelope)
        XCTAssertNil(estimate)
    }

    func test_snapToStandardBPH_picks_nearest_within_tolerance() {
        XCTAssertEqual(BPHEstimator.nearestStandardBPH(28_750), 28_800)
        XCTAssertEqual(BPHEstimator.nearestStandardBPH(28_850), 28_800)
        XCTAssertEqual(BPHEstimator.nearestStandardBPH(21_500), 21_600)
        XCTAssertEqual(BPHEstimator.nearestStandardBPH(35_500), 36_000)
    }

    private func makeEnvelope(_ raw: [Float]) -> [Float] {
        let pre = PreEmphasisFilter()
        let bp = BandPassFilter()
        let env = EnvelopeExtractor()
        let stage1 = pre.process(raw)
        let stage2 = bp.process(stage1)
        return env.process(stage2)
    }
}
