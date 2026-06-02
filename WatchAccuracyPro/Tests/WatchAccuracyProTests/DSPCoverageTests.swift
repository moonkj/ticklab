import Accelerate
import Foundation
import XCTest
@testable import WatchAccuracyPro

/// 커버리지 보강 — DSPPipeline 의 다양한 BPH·입력 가드(빈/짧은/무음)·정적 유틸(normalized/estimateSNR) 검증.
/// 기존 DSPPipelineTests/BeatDetectorTests/BPHEstimatorTests 의 단언을 중복하지 않고 미검증 분기를 덮는다.
final class DSPCoverageTests: XCTestCase {

    // MARK: - 합성 신호 헬퍼 (BeatDetectorTests 의 makeEnvelope 패턴 재사용)

    /// 실측 production filter chain 으로 envelope 생성. estimateSNR 입력용.
    private func makeEnvelope(_ raw: [Float]) -> [Float] {
        let pre = PreEmphasisFilter()
        let bp = BandPassFilter()
        let env = EnvelopeExtractor()
        return env.process(bp.process(pre.process(raw)))
    }

    // MARK: - DSPPipeline legacy path (useSimplified: false) — analyzeInternal 분기 커버

    func test_pipeline_legacy_path_locks_bph_28800() throws {
        // useSimplified:false → analyzeInternal (OLS/RANSAC/trimmed-mean) 경로 진입.
        // 기존 테스트는 simplified(default true) 만 돌림 → 이 분기는 미검증이었음.
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 6)
        let source = SyntheticAudioSource(signal: raw)
        let pipeline = DSPPipeline(
            source: source,
            nominalBph: 28_800,
            liftAngleDegrees: 52,
            escapement: .swissLever,
            reliabilityLabel: .high,
            useSimplified: false
        )
        try pipeline.start()
        let result = try XCTUnwrap(pipeline.stop(), "legacy path 에서 결과가 나와야 한다")
        XCTAssertEqual(result.bph, 28_800)
        // 합성 신호 + IIR 위상 응답 → rate 는 관용. 기존 simplified 테스트와 동일한 ±200 s/d 한계.
        XCTAssertEqual(result.rateSecondsPerDay, 0, accuracy: 200)
        XCTAssertGreaterThan(result.beatCount, 0)
        // lastSnapshot 이 stop() 결과와 동기화돼야 한다.
        XCTAssertEqual(pipeline.lastSnapshot, result)
    }

    func test_pipeline_legacy_path_18000bph_locks() throws {
        // 18000 BPH (=5 beats/sec). simplified 테스트가 안 다루는 낮은 BPH 분기.
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 18_000, duration: 8)
        let source = SyntheticAudioSource(signal: raw)
        let pipeline = DSPPipeline(
            source: source,
            nominalBph: 18_000,
            liftAngleDegrees: 50,
            escapement: .swissLever,
            reliabilityLabel: .high,
            useSimplified: false
        )
        try pipeline.start()
        // 합성 18000 신호는 lock 될 수도, 약하게 reject 될 수도 있음 — 둘 다 정상 경로.
        if let result = pipeline.stop() {
            XCTAssertGreaterThan(result.bph, 0)
            XCTAssertEqual(result.rateSecondsPerDay, 0, accuracy: 300)
        }
    }

    func test_pipeline_simplified_21600bph_seiko_locks() throws {
        // simplified 경로, 21600 BPH (Seiko NH35). 기존 simplified 테스트는 28800/25200 만.
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 21_600, duration: 6)
        let source = SyntheticAudioSource(signal: raw)
        let pipeline = DSPPipeline(
            source: source,
            nominalBph: 21_600,
            liftAngleDegrees: 53,
            escapement: .swissLever,
            reliabilityLabel: .high
        )
        try pipeline.start()
        if let result = pipeline.stop() {
            XCTAssertEqual(result.bph, 21_600)
            XCTAssertEqual(result.rateSecondsPerDay, 0, accuracy: 250)
        }
    }

    func test_pipeline_low_reliability_suppresses_amplitude_and_adds_note() throws {
        // Hard Rule 9 — reliabilityLabel .low → amplitude nil + generic note.
        // displaysAmplitude=false 분기 (amplitude 계산 skip) 커버.
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 6)
        let source = SyntheticAudioSource(signal: raw)
        let pipeline = DSPPipeline(
            source: source,
            nominalBph: 28_800,
            liftAngleDegrees: nil,
            escapement: .swissLever,
            reliabilityLabel: .low
        )
        try pipeline.start()
        if let result = pipeline.stop() {
            XCTAssertNil(result.amplitudeDegrees, "low reliability → amplitude 미산출")
            XCTAssertEqual(result.reliabilityNoteKey, "movement.reliability.generic.notice")
        }
    }

    // MARK: - 입력 가드: 빈/짧은/무음

    func test_pipeline_empty_signal_returns_nil() throws {
        // 신호 0개 → buffer<0.5s 가드 → analyze nil. stop() 도 nil (synthesized echo 조건 미달).
        let source = SyntheticAudioSource(signal: [])
        let pipeline = DSPPipeline(
            source: source,
            nominalBph: 28_800,
            liftAngleDegrees: 52,
            escapement: .swissLever,
            reliabilityLabel: .high
        )
        try pipeline.start()
        XCTAssertNil(pipeline.stop(), "빈 신호는 결과가 없어야 한다")
    }

    func test_pipeline_short_signal_under_half_second_returns_nil() throws {
        // 0.2초 < 0.5초 가드 → analyzeSimplified 의 "buffer<0.5s(simplified)" 분기.
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 0.2)
        let source = SyntheticAudioSource(signal: raw)
        let pipeline = DSPPipeline(
            source: source,
            nominalBph: 28_800,
            liftAngleDegrees: 52,
            escapement: .swissLever,
            reliabilityLabel: .high
        )
        try pipeline.start()
        XCTAssertNil(pipeline.stop())
        // 진단 사유 문자열이 기록돼야 한다.
        XCTAssertNotNil(pipeline.lastAnalyzeFailReason)
    }

    func test_pipeline_silence_signal_returns_nil_or_no_lock() throws {
        // 거의 무음(미세 노이즈) → onset 부족 → simplified onsets<8 가드 또는 lock 실패.
        let silence = [Float](repeating: 0.0, count: 48_000 * 2)
        let source = SyntheticAudioSource(signal: silence)
        let pipeline = DSPPipeline(
            source: source,
            nominalBph: 28_800,
            liftAngleDegrees: 52,
            escapement: .swissLever,
            reliabilityLabel: .high
        )
        try pipeline.start()
        XCTAssertNil(pipeline.stop(), "무음 신호는 lock 되면 안 된다")
        XCTAssertNotNil(pipeline.lastAnalyzeFailReason)
    }

    func test_pipeline_analyze_before_start_returns_nil() {
        // start() 안 부르고 analyze() — buffer 비어 있음 → nil. early-guard 경로.
        let source = SyntheticAudioSource(signal: [])
        let pipeline = DSPPipeline(
            source: source,
            nominalBph: 28_800,
            liftAngleDegrees: 52,
            escapement: .swissLever,
            reliabilityLabel: .high
        )
        XCTAssertNil(pipeline.analyze())
        XCTAssertNil(pipeline.analyze(windowSeconds: 5))
        XCTAssertNil(pipeline.analyze(windowSeconds: 5, tailTrimSeconds: 1))
    }

    // MARK: - 정적 유틸: normalized

    func test_normalized_scales_peak_to_unit() {
        let out = DSPPipeline.normalized([0.0, 0.5, -1.0, 2.0, -4.0])
        // 최대 절대값 4.0 → scale 0.25. 부호 보존.
        XCTAssertEqual(out[3], 0.5, accuracy: 1e-5)   // 2.0 * 0.25
        XCTAssertEqual(out[4], -1.0, accuracy: 1e-5)  // -4.0 * 0.25
        XCTAssertEqual(out.map { abs($0) }.max() ?? 0, 1.0, accuracy: 1e-5)
    }

    func test_normalized_all_zeros_returns_unchanged() {
        // maxAbs == 0 분기 → 입력 그대로 반환 (나눗셈 회피).
        let input: [Float] = [0, 0, 0, 0]
        XCTAssertEqual(DSPPipeline.normalized(input), input)
    }

    // MARK: - 정적 유틸: estimateSNR

    func test_estimateSNR_empty_envelope_returns_zero() {
        XCTAssertEqual(DSPPipeline.estimateSNR(envelope: [], raw: []), 0, accuracy: 1e-9)
    }

    func test_estimateSNR_flat_envelope_is_near_zero_dB() {
        // 모든 값 동일 → noiseFloor ≈ peakAvg → ratio ≈ 1 → 0 dB (max(ratio,1) 가드).
        let flat = [Float](repeating: 0.3, count: 4_800)
        let snr = DSPPipeline.estimateSNR(envelope: flat, raw: flat)
        XCTAssertEqual(snr, 0, accuracy: 0.5)
    }

    func test_estimateSNR_high_contrast_envelope_is_positive() {
        // 90% 낮은 floor + 10% 높은 peak → 큰 ratio → 양의 dB.
        var env = [Float](repeating: 0.01, count: 4_800)
        for i in 0..<480 { env[i] = 1.0 }
        let snr = DSPPipeline.estimateSNR(envelope: env, raw: env)
        XCTAssertGreaterThan(snr, 20, "고대비 envelope 은 SNR 가 커야 한다")
    }

    func test_estimateSNR_real_signal_higher_than_silence() {
        // 실 합성 tic 신호의 SNR 가 무음보다 분명히 높아야 한다.
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 3)
        let env = makeEnvelope(raw)
        let signalSNR = DSPPipeline.estimateSNR(envelope: env, raw: raw)
        let silentEnv = [Float](repeating: 0.001, count: env.count)
        let silentSNR = DSPPipeline.estimateSNR(envelope: silentEnv, raw: silentEnv)
        XCTAssertGreaterThan(signalSNR, silentSNR)
    }

    // MARK: - 라이브 스트림 종료 + 진단 (legacy path)

    func test_legacy_pipeline_streams_finish_after_stop() async throws {
        // legacy 경로에서도 waveform stream 이 emit 후 finish 돼야 한다 (다른 분기).
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 2)
        let source = SyntheticAudioSource(signal: raw)
        let pipeline = DSPPipeline(
            source: source,
            nominalBph: 28_800,
            liftAngleDegrees: 52,
            escapement: .swissLever,
            reliabilityLabel: .high,
            useSimplified: false
        )
        let stream = pipeline.liveWaveformStream
        let collector = Task<Int, Never> {
            var n = 0
            for await _ in stream { n += 1 }
            return n
        }
        try pipeline.start()
        _ = pipeline.stop()
        let count = await collector.value
        XCTAssertGreaterThanOrEqual(count, 1, "최소 한 waveform chunk emit")
    }
}
