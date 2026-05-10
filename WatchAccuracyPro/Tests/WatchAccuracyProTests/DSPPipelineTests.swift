import XCTest
@testable import WatchAccuracyPro

final class DSPPipelineTests: XCTestCase {
    func test_pipeline_eta2824_produces_high_confidence_correct_bph() throws {
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 5)
        let source = SyntheticAudioSource(signal: raw)
        let pipeline = DSPPipeline(
            source: source,
            nominalBph: 28_800,
            liftAngleDegrees: 52,
            escapement: .swissLever,
            reliabilityLabel: .high
        )
        try pipeline.start()
        let result = pipeline.stop()

        let unwrapped = try XCTUnwrap(result)
        XCTAssertEqual(unwrapped.bph, 28_800)
        XCTAssertEqual(unwrapped.rateSecondsPerDay, 0, accuracy: 5)
        XCTAssertEqual(unwrapped.beatErrorMs, 0, accuracy: 0.5)
        XCTAssertGreaterThan(unwrapped.confidenceScore, 50)
        XCTAssertNil(unwrapped.reliabilityNoteKey, "swissLever + high → reliability note 없음")
    }

    func test_pipeline_coaxial_returns_nil_amplitude_with_notice() throws {
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 25_200, duration: 5)
        let source = SyntheticAudioSource(signal: raw)
        let pipeline = DSPPipeline(
            source: source,
            nominalBph: 25_200,
            liftAngleDegrees: 38,
            escapement: .coAxial,
            reliabilityLabel: .medium
        )
        try pipeline.start()
        let result = try XCTUnwrap(pipeline.stop())
        XCTAssertEqual(result.bph, 25_200)
        XCTAssertNil(result.amplitudeDegrees, "코악시얼은 amplitude 미산출")
        XCTAssertEqual(result.reliabilityNoteKey, "movement.reliability.coaxial.notice")
    }

    func test_pipeline_with_drift_signal_reports_correct_rate() throws {
        // 28800 BPH 명목인데 실제로는 28829 BPH 신호 (약 +87초/일)
        let drifted = SyntheticSignal.ticTocImpulseTrain(bph: 28_829, duration: 5)
        let source = SyntheticAudioSource(signal: drifted)
        let pipeline = DSPPipeline(
            source: source,
            nominalBph: 28_800,
            liftAngleDegrees: 52,
            escapement: .swissLever,
            reliabilityLabel: .high
        )
        try pipeline.start()
        let result = try XCTUnwrap(pipeline.stop())
        // BPH 스냅 후 28800으로 강제 스냅될 가능성도 있어 raw로 평가
        XCTAssertEqual(result.rateSecondsPerDay, 87.0, accuracy: 30,
                       "약 +87초/일 근방에서 검출돼야 한다 — got \(result.rateSecondsPerDay)")
    }
}
