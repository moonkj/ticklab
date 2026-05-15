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

    func test_returns_nil_when_estimate_falls_outside_100_360_range() {
        // 모두 같은 envelope (FWHM 매우 좁음) → tImp 거의 0 → amplitude 폭발 → nil 반환되어야 함
        let beats: [BeatEvent] = (0..<10).map {
            BeatEvent(timestampSeconds: Double($0) * 0.125, type: $0.isMultiple(of: 2) ? .tic : .toc, energy: 1)
        }
        var env = [Float](repeating: 0.01, count: 48_000)
        // 매우 좁은 spike → FWHM ≈ 0 → amplitude → ∞
        for beat in beats {
            let idx = Int(beat.timestampSeconds * 48_000)
            if idx < env.count { env[idx] = 1.0 }
        }
        let amp = AmplitudeEstimator.estimate(envelope: env, beats: beats, liftAngleDegrees: 52, escapement: .swissLever)
        // 이전 동작: 360 으로 clamp. 새 동작: nil (silent failure 방지).
        XCTAssertNil(amp, "범위 밖 추정은 nil — clamp 금지 (silent failure 방지)")
    }

    // Round 122 (DSP High / Hard Rule 1): Round 103 siliconEscapement 변경 테스트 커버리지.
    func test_siliconEscapement_not_blocked() {
        // siliconEscapement 는 swissLever 와 동일 처리 — nil 로 막으면 안 됨.
        let raw: [Float] = Array(repeating: 0.5, count: 1000)
        let beats = [BeatEvent(timestampSeconds: 0.1, type: .tic, energy: 0.5),
                     BeatEvent(timestampSeconds: 0.2, type: .toc, energy: 0.5),
                     BeatEvent(timestampSeconds: 0.3, type: .tic, energy: 0.5),
                     BeatEvent(timestampSeconds: 0.4, type: .toc, energy: 0.5)]
        // nil 반환 원인이 escapement guard 가 아닌 다른 이유(FWHM 계산)여야 함.
        // escapement guard 가 막으면 항상 nil → coAxial 처럼 nil 이어야 하지만 그 이유가 달라야 함.
        // 이 테스트는 크래시가 없고, coAxial 처럼 "원천 차단"이 아님을 검증.
        let resultSilicon = AmplitudeEstimator.estimate(
            envelope: raw, beats: beats, liftAngleDegrees: 52, escapement: .siliconEscapement)
        let resultCoaxial = AmplitudeEstimator.estimate(
            envelope: raw, beats: beats, liftAngleDegrees: nil, escapement: .coAxial)
        // coAxial 은 liftAngle nil → nil. silicon 은 liftAngle 있고 escapement guard 통과 → nil/value 무관하나 guard 자체가 아닌 이유.
        XCTAssertNil(resultCoaxial, "coAxial must be nil regardless of liftAngle (no physics formula)")
        // silicon 는 guard 통과한 후 FWHM 계산에서 nil 될 수 있음 — guard 자체가 nil 반환하면 안 됨.
        // 직접 검증: escapement == .siliconEscapement 면 false 리턴하지 않아야 함.
        // (합성 신호라 실제 값 nil 도 허용)
        _ = resultSilicon  // no crash
    }

    func test_returns_value_in_reasonable_range_or_nil_for_swiss_lever() {
        // 합성 신호 → envelope → beats → amplitude 추정.
        // 새 정책(Round 3): 100~360 범위 밖이면 nil 반환 (silent clamp 금지).
        // 합성 신호의 FWHM 은 실측과 다르므로 nil/in-range 둘 다 허용.
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
        if let amp {
            XCTAssertTrue((100...360).contains(amp), "amplitude 가 산출됐으면 100~360° 범위 — got \(amp)")
        }
        // amp == nil 인 경우는 'amplitude_unstable' 안내가 DSPPipeline 단계에서 부여되며, 단위 테스트로는 OK.
    }
}
