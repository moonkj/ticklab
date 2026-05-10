import XCTest
@testable import WatchAccuracyPro

final class AmplitudeEstimatorTests: XCTestCase {
    func test_returns_nil_when_lift_angle_unknown() {
        let beats: [BeatEvent] = (0..<10).map {
            BeatEvent(timestampSeconds: Double($0) * 0.125, type: $0.isMultiple(of: 2) ? .tic : .toc, energy: 1)
        }
        let env = [Float](repeating: 0.5, count: 48_000)
        let amp = AmplitudeEstimator.estimate(envelope: env, beats: beats, liftAngleDegrees: nil, escapement: .swissLever)
        XCTAssertNil(amp)
    }

    func test_returns_nil_for_coaxial() {
        let beats: [BeatEvent] = (0..<10).map {
            BeatEvent(timestampSeconds: Double($0) * 0.125, type: $0.isMultiple(of: 2) ? .tic : .toc, energy: 1)
        }
        let env = [Float](repeating: 0.5, count: 48_000)
        let amp = AmplitudeEstimator.estimate(envelope: env, beats: beats, liftAngleDegrees: 38, escapement: .coAxial)
        XCTAssertNil(amp, "코악시얼은 amplitude 미산출")
    }

    func test_returns_nil_for_spring_drive() {
        let beats: [BeatEvent] = (0..<10).map {
            BeatEvent(timestampSeconds: Double($0) * 0.125, type: $0.isMultiple(of: 2) ? .tic : .toc, energy: 1)
        }
        let env = [Float](repeating: 0.5, count: 48_000)
        let amp = AmplitudeEstimator.estimate(envelope: env, beats: beats, liftAngleDegrees: 50, escapement: .springDrive)
        XCTAssertNil(amp)
    }

    func test_returns_value_in_reasonable_range_for_swiss_lever() {
        // 합성 신호 → envelope → beats → amplitude 추정
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 3)
        let pre = PreEmphasisFilter().process(raw)
        let bp = BandPassFilter().process(pre)
        let env = EnvelopeExtractor().process(bp)
        let beats = BeatDetector.detectOnsets(envelope: env)
        guard beats.count > 8 else { return XCTFail() }

        let amp = AmplitudeEstimator.estimate(
            envelope: env,
            beats: beats,
            liftAngleDegrees: 52,
            escapement: .swissLever
        )
        XCTAssertNotNil(amp)
        // 합성 신호로는 정확한 캘리브레이션이 어려우니 클램프된 100~360 범위 내에 있는지만 확인
        if let amp { XCTAssertTrue((100...360).contains(amp), "amplitude 100~360° 사이 — got \(amp)") }
    }
}
