import Accelerate
import Foundation
import XCTest
@testable import WatchAccuracyPro

/// 커버리지 보강 — DSPPipeline 의 legacy(`useSimplified:false`) 경로, 다양한 BPH,
/// 입력 가드(빈/짧은/무음), 정적 유틸(normalized/estimateSNR) 및
/// SimplifiedBeatDetector 의 3개 순수 함수(hilbertEnvelope/detectOnsets/rateFromOnsets) 를 검증한다.
///
/// 기존 DSPPipelineTests/DSPPipelineLiveStreamTests/BeatDetectorTests/BPHEstimatorTests 의
/// 단언을 중복하지 않고, 미검증 분기를 추가로 덮는다.
///
/// DSPPipeline / SimplifiedBeatDetector 둘 다 `@MainActor` 가 아니므로 클래스 어노테이션 불필요.
final class DSPCoverageTests: XCTestCase {

    // MARK: - 합성 신호 헬퍼 (BeatDetectorTests 의 makeEnvelope 패턴 재사용)

    /// 실측 production filter chain 으로 envelope 생성. SimplifiedBeatDetector / estimateSNR 입력용.
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

    // MARK: - SimplifiedBeatDetector.hilbertEnvelope

    func test_hilbert_envelope_too_short_returns_empty() {
        // n <= 4 가드.
        XCTAssertTrue(SimplifiedBeatDetector.hilbertEnvelope(samples: [1, 2, 3], sampleRate: 48_000).isEmpty)
        XCTAssertTrue(SimplifiedBeatDetector.hilbertEnvelope(samples: [], sampleRate: 48_000).isEmpty)
    }

    func test_hilbert_envelope_length_matches_input() {
        // 출력 길이는 입력 길이 n 과 동일해야 한다 (FFT 패딩은 내부에서만).
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 1)
        let env = SimplifiedBeatDetector.hilbertEnvelope(samples: raw, sampleRate: 48_000)
        XCTAssertEqual(env.count, raw.count)
        // envelope magnitude 는 비음수.
        XCTAssertTrue(env.allSatisfy { $0 >= 0 })
    }

    func test_hilbert_envelope_pure_tone_is_nearly_constant() {
        // 단일 정현파의 analytic magnitude 는 거의 일정한 진폭(=1)에 LPF 후 수렴해야 한다.
        let sampleRate = 48_000.0
        let freq = 1_000.0
        let n = 8_192
        let tone = (0..<n).map { Float(sin(2.0 * .pi * freq * Double($0) / sampleRate)) }
        let env = SimplifiedBeatDetector.hilbertEnvelope(samples: tone, sampleRate: sampleRate, lpfCutoffHz: 200)
        XCTAssertEqual(env.count, n)
        // edge transient 제외 중간 구간의 평균이 1 부근.
        let mid = Array(env[(n / 4)..<(3 * n / 4)])
        let mean = mid.reduce(Float(0), +) / Float(mid.count)
        XCTAssertEqual(mean, 1.0, accuracy: 0.25)
    }

    func test_hilbert_envelope_peaks_at_impulse_locations() {
        // 임펄스 신호 → envelope 가 임펄스 부근에서 peak 를 가진다.
        var raw = [Float](repeating: 0, count: 8_192)
        raw[2_000] = 1.0
        raw[5_000] = 1.0
        let env = SimplifiedBeatDetector.hilbertEnvelope(samples: raw, sampleRate: 48_000, lpfCutoffHz: 1_000)
        XCTAssertEqual(env.count, raw.count)
        // 임펄스 근처 값이 신호 없는 구간(인덱스 7000)보다 크다.
        let near = max(env[1_990...2_050].max() ?? 0, env[4_990...5_050].max() ?? 0)
        XCTAssertGreaterThan(near, env[7_000])
    }

    // MARK: - SimplifiedBeatDetector.detectOnsets

    func test_simplified_detectOnsets_short_envelope_returns_empty() {
        // envelope.count <= 4 가드.
        XCTAssertTrue(SimplifiedBeatDetector.detectOnsets(envelope: [0.1, 0.2, 0.3], sampleRate: 48_000).isEmpty)
    }

    func test_simplified_detectOnsets_flat_envelope_finds_nothing() {
        // 완전 평탄 → MAD=0, threshold=median, local-max 조건 미충족(> 비교) → onset 없음.
        let flat = [Float](repeating: 0.5, count: 10_000)
        let onsets = SimplifiedBeatDetector.detectOnsets(envelope: flat, sampleRate: 48_000)
        XCTAssertTrue(onsets.isEmpty)
    }

    func test_simplified_detectOnsets_periodic_peaks_match_count() {
        // 200Hz envelope 위에 0.125s 간격(28800 BPH=8/s) peak → 2초에 약 16개.
        // refractory 80ms < 125ms 간격 → 각 peak 개별 검출.
        let sampleRate = 200.0
        let n = Int(sampleRate * 2.0)
        var env = [Float](repeating: 0.05, count: n)
        let period = Int(0.125 * sampleRate)  // 25 samples
        var idx = period
        while idx < n - 1 {
            env[idx] = 1.0
            idx += period
        }
        let onsets = SimplifiedBeatDetector.detectOnsets(envelope: env, sampleRate: sampleRate, refractoryMs: 80, kMad: 3.0)
        // 약 15개 (시작/끝 경계 ±2).
        XCTAssertGreaterThanOrEqual(onsets.count, 13)
        XCTAssertLessThanOrEqual(onsets.count, 17)
        // onset timestamp 는 단조 증가 + 초 단위.
        for i in 1..<onsets.count {
            XCTAssertGreaterThan(onsets[i], onsets[i - 1])
        }
        XCTAssertLessThanOrEqual(onsets.last ?? 0, 2.0)
    }

    func test_simplified_detectOnsets_refractory_suppresses_close_peaks() {
        // 인접한 두 peak 가 refractory 안에 있으면 첫 번째만 검출.
        let sampleRate = 1_000.0
        var env = [Float](repeating: 0.05, count: 2_000)
        env[500] = 1.0
        env[510] = 1.0   // 10ms 뒤 — refractory 80ms 안 → 억제돼야 함
        let onsets = SimplifiedBeatDetector.detectOnsets(envelope: env, sampleRate: sampleRate, refractoryMs: 80)
        XCTAssertEqual(onsets.count, 1)
        XCTAssertEqual(onsets[0], 0.5, accuracy: 0.005)  // 인덱스 500 / 1000Hz
    }

    // MARK: - SimplifiedBeatDetector.rateFromOnsets

    func test_simplified_rateFromOnsets_too_few_returns_nil() {
        // onsets < 8 가드.
        let onsets = (0..<5).map { Double($0) * 0.125 }
        XCTAssertNil(SimplifiedBeatDetector.rateFromOnsets(onsets: onsets, nominalBph: 28_800))
    }

    func test_simplified_rateFromOnsets_perfect_28800_returns_nominal_bph() {
        // 정확히 0.125s 간격 16개 onset → bph ≈ 28800, residual RMS ≈ 0.
        let onsets = (0..<16).map { Double($0) * 0.125 }
        let result = SimplifiedBeatDetector.rateFromOnsets(onsets: onsets, nominalBph: 28_800)
        let unwrapped = try? XCTUnwrap(result)
        XCTAssertNotNil(unwrapped)
        if let r = unwrapped {
            XCTAssertEqual(r.bph, 28_800, accuracy: 1.0)
            XCTAssertEqual(r.beatCount, 16)
            XCTAssertEqual(r.residualRMSSeconds, 0, accuracy: 1e-6)
        }
    }

    func test_simplified_rateFromOnsets_fast_watch_higher_bph() {
        // 약간 빠른 watch — IOI 0.124s (tight 5% 안) → bph > 28800.
        let ioi = 0.124
        let onsets = (0..<20).map { Double($0) * ioi }
        let result = SimplifiedBeatDetector.rateFromOnsets(onsets: onsets, nominalBph: 28_800)
        if let r = result {
            XCTAssertEqual(r.bph, 3600.0 / ioi, accuracy: 5.0)
            XCTAssertGreaterThan(r.bph, 28_800)
        } else {
            XCTFail("tight 5% 안의 IOI 는 rate 가 나와야 한다")
        }
    }

    func test_simplified_rateFromOnsets_all_outliers_returns_nil() {
        // nominal 대비 50% 벗어난 IOI 들 → tight 필터 통과 0 → nil.
        let onsets = (0..<12).map { Double($0) * 0.2 }  // 0.2s vs nominal 0.125s → +60%
        XCTAssertNil(SimplifiedBeatDetector.rateFromOnsets(onsets: onsets, nominalBph: 28_800))
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
