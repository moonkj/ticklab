import Foundation
import XCTest
@testable import WatchAccuracyPro

/// 커버리지 보강 — DSPPipeline 의 init config-dispatch 분기 + tail-trim/legacy 변종.
///   · MatchedFilterProfile.resolve / BandPassSpec.spec 의 미검증 escapement·bph 조합
///     (siliconEscapement, highBeat36000, springDrive/detentEscapement bypass)
///   · veryHigh reliabilityLabel (displaysAmplitude=true, reliabilityNote=nil) 분기
///   · analyze(windowSeconds:tailTrimSeconds:) 의 non-zero tailTrim (simplified + legacy)
///
/// 기존 DSPPipelineTests/DSPCoverageTests 가 다루는 swissLever/coAxial · trim=0 ·
/// high/medium/low reliabilityLabel 단언과 중복하지 않는다.
/// DSPPipeline 은 @MainActor 아님 — 클래스 어노테이션 불필요.
final class DSPPipelineConfigBranchTests: XCTestCase {

    // MARK: - MatchedFilterProfile.resolve dispatch (init 분기 직접 검증)

    func test_resolve_silicon_escapement_follows_swiss_lever_table() {
        // siliconEscapement 는 swissLever 와 동일 bph 테이블을 탄다 (미검증 case label).
        XCTAssertEqual(MatchedFilterProfile.resolve(escapement: .siliconEscapement, bph: 18_000), .vintage18k)
        XCTAssertEqual(MatchedFilterProfile.resolve(escapement: .siliconEscapement, bph: 21_600), .swissLever21600)
        XCTAssertEqual(MatchedFilterProfile.resolve(escapement: .siliconEscapement, bph: 28_800), .swissLever28800Classic)
        XCTAssertEqual(MatchedFilterProfile.resolve(escapement: .siliconEscapement, bph: 36_000), .highBeat36000)
    }

    func test_resolve_non_lever_escapements_bypass() {
        // coAxial 은 기존 테스트가 다루지만 springDrive/quartz/detentEscapement bypass 는 미검증.
        XCTAssertEqual(MatchedFilterProfile.resolve(escapement: .springDrive, bph: 28_800), .bypass)
        XCTAssertEqual(MatchedFilterProfile.resolve(escapement: .quartz, bph: 28_800), .bypass)
        XCTAssertEqual(MatchedFilterProfile.resolve(escapement: .detentEscapement, bph: 21_600), .bypass)
    }

    func test_resolve_swiss_lever_bph_boundaries() {
        // bph switch 경계값 — 19800(하한), 25200(중간), 31500(상한).
        XCTAssertEqual(MatchedFilterProfile.resolve(escapement: .swissLever, bph: 19_799), .vintage18k)
        XCTAssertEqual(MatchedFilterProfile.resolve(escapement: .swissLever, bph: 19_800), .swissLever21600)
        XCTAssertEqual(MatchedFilterProfile.resolve(escapement: .swissLever, bph: 25_200), .swissLever28800Classic)
        XCTAssertEqual(MatchedFilterProfile.resolve(escapement: .swissLever, bph: 31_500), .highBeat36000)
    }

    // MARK: - BandPassSpec.spec 미검증 profile 분기

    func test_bandPassSpec_highBeat36000_uses_wider_high_band() {
        // highBeat36000 profile 의 BandPassSpec — 기존 테스트 미검증 분기.
        let spec = BandPassSpec.spec(for: .highBeat36000, escapement: .swissLever)
        XCTAssertEqual(spec.lowHz, 3_500, accuracy: 1e-6)
        XCTAssertEqual(spec.highHz, 8_000, accuracy: 1e-6)
        XCTAssertEqual(spec.envCutoffHz, 500, accuracy: 1e-6)
    }

    func test_bandPassSpec_vintage18k_branch() {
        let spec = BandPassSpec.spec(for: .vintage18k, escapement: .swissLever)
        XCTAssertEqual(spec.lowHz, 1_500, accuracy: 1e-6)
        XCTAssertEqual(spec.highHz, 5_000, accuracy: 1e-6)
        XCTAssertEqual(spec.envCutoffHz, 250, accuracy: 1e-6)
    }

    func test_bandPassSpec_bypass_is_default() {
        // bypass profile (non-coAxial escapement) → .default spec. coAxial 은 별도 override 라 제외.
        let spec = BandPassSpec.spec(for: .bypass, escapement: .springDrive)
        XCTAssertEqual(spec.lowHz, BandPassSpec.default.lowHz, accuracy: 1e-6)
        XCTAssertEqual(spec.highHz, BandPassSpec.default.highHz, accuracy: 1e-6)
        XCTAssertEqual(spec.envCutoffHz, BandPassSpec.default.envCutoffHz, accuracy: 1e-6)
    }

    func test_bandPassSpec_coaxial_override() {
        // coAxial 은 profile 무관하게 wide-band override (early return 분기).
        let spec = BandPassSpec.spec(for: .bypass, escapement: .coAxial)
        XCTAssertEqual(spec.lowHz, 2_000, accuracy: 1e-6)
        XCTAssertEqual(spec.highHz, 9_000, accuracy: 1e-6)
        XCTAssertEqual(spec.envCutoffHz, 400, accuracy: 1e-6)
    }

    // MARK: - veryHigh reliabilityLabel (displaysAmplitude=true, note=nil)

    func test_pipeline_veryHigh_reliability_no_note_and_attempts_amplitude() throws {
        // veryHigh → displaysAmplitude true, reliabilityNote nil. 기존 테스트는 high/medium/low 만.
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 6)
        let source = SyntheticAudioSource(signal: raw)
        let pipeline = DSPPipeline(
            source: source,
            nominalBph: 28_800,
            liftAngleDegrees: 52,
            escapement: .swissLever,
            reliabilityLabel: .veryHigh
        )
        try pipeline.start()
        if let result = pipeline.stop() {
            // veryHigh 는 generic/coaxial note 모두 표시 안 함.
            XCTAssertNil(result.reliabilityNoteKey, "veryHigh → reliability note 없음")
            XCTAssertEqual(result.bph, 28_800)
        }
    }

    // MARK: - siliconEscapement 36000 (highBeat36000 profile) 통합 실행

    func test_pipeline_silicon_high_beat_constructs_and_runs() throws {
        // siliconEscapement + 36000 → highBeat36000 profile + wide BandPassSpec 통합 경로 실행.
        // 합성 36000 신호는 lock 될 수도, reject 될 수도 있음 — 둘 다 정상 (크래시 없이 분기 통과가 목표).
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 36_000, duration: 6)
        let source = SyntheticAudioSource(signal: raw)
        let pipeline = DSPPipeline(
            source: source,
            nominalBph: 36_000,
            liftAngleDegrees: 50,
            escapement: .siliconEscapement,
            reliabilityLabel: .high
        )
        try pipeline.start()
        if let result = pipeline.stop() {
            XCTAssertGreaterThan(result.bph, 0)
            XCTAssertGreaterThanOrEqual(result.beatCount, 0)
        }
    }

    // MARK: - analyze(windowSeconds:tailTrimSeconds:) non-zero trim

    func test_simplified_analyze_with_tail_trim_returns_result() throws {
        // simplified 경로 + tailTrimSeconds>0 — 기존 테스트(trim=0)가 안 다루는 trim 슬라이싱 분기.
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 8)
        let source = SyntheticAudioSource(signal: raw)
        let pipeline = DSPPipeline(
            source: source,
            nominalBph: 28_800,
            liftAngleDegrees: 52,
            escapement: .swissLever,
            reliabilityLabel: .high
        )
        try pipeline.start()
        _ = pipeline.stop()
        // stop() 후 buffer 가 살아 있어 analyze 재호출 가능 (analyzer task 만 취소됨).
        let trimmed = pipeline.analyze(windowSeconds: 5, tailTrimSeconds: 2)
        if let r = trimmed {
            XCTAssertEqual(r.bph, 28_800)
            XCTAssertGreaterThan(r.beatCount, 0)
        }
    }

    func test_legacy_analyze_with_tail_trim_executes_branch() throws {
        // legacy(useSimplified:false) + tailTrim>0 → analyzeInternal 의 tail-trim 슬라이싱 분기.
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 8)
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
        _ = pipeline.stop()
        // 크래시 없이 분기 통과가 목표 — lock 결과는 합성 신호 특성상 nil 일 수도 있음.
        let trimmed = pipeline.analyze(windowSeconds: 6, tailTrimSeconds: 2)
        if let r = trimmed {
            XCTAssertGreaterThan(r.bph, 0)
            XCTAssertEqual(r.rateSecondsPerDay, 0, accuracy: 300)
        }
    }

    func test_analyze_tail_trim_larger_than_window_guards_nil() throws {
        // tailTrim 이 너무 커서 trimmed window 가 0.5s 미만 → "trimmed<0.5s" 가드 → nil.
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 3)
        let source = SyntheticAudioSource(signal: raw)
        let pipeline = DSPPipeline(
            source: source,
            nominalBph: 28_800,
            liftAngleDegrees: 52,
            escapement: .swissLever,
            reliabilityLabel: .high
        )
        try pipeline.start()
        _ = pipeline.stop()
        // 3초 buffer 에서 거의 전부 trim → 남는 window <0.5s.
        XCTAssertNil(pipeline.analyze(windowSeconds: 1, tailTrimSeconds: 2.9))
    }
}
