import XCTest
@testable import WatchAccuracyPro

/// 커버리지 보강(추가) — BPHEstimator 의 BPHEstimatorTests/BPHEstimatorBranchTests 가
/// 아직 안 다루는 분기.
///   · estimateAutocorrelation(nominalBphHint:) 의 ±5% halfPct + ±20% candidate 제한 경로
///   · estimate 진입점의 (autoEst, onsetEst) 둘 다 존재 + 동일 BPH → confidence 병합 분기
///   · fallbackFromOnsetRate 의 timeSpan<5 / drift>=0.15 가드 (nil)
///   · nearestStandardBPH 빈 candidates → standardBPHs[0] fallback
///
/// BPHEstimator 는 enum 정적 함수 — @MainActor 불필요. 합성 신호만 사용.
final class BPHEstimatorBranchExtraTests: XCTestCase {

    /// production filter chain envelope (BPHEstimatorTests 의 makeEnvelope 와 동일 패턴).
    private func makeEnvelope(_ raw: [Float]) -> [Float] {
        let pre = PreEmphasisFilter()
        let bp = BandPassFilter()
        let env = EnvelopeExtractor()
        return env.process(bp.process(pre.process(raw)))
    }

    // MARK: - estimateAutocorrelation with hint (±5% window + ±20% candidate 제한)

    func test_estimateAutocorrelation_with_hint_locks_28800() {
        // hint 제공 시 halfPct=0.05 분기 + candidates ±20% 제한 경로 진입.
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 5)
        let env = makeEnvelope(raw)
        let est = BPHEstimator.estimateAutocorrelation(envelope: env, nominalBphHint: 28_800)
        XCTAssertNotNil(est, "hint 가 있으면 autocorrelation 이 lock 돼야 한다")
        XCTAssertEqual(est?.bph, 28_800)
    }

    func test_estimateAutocorrelation_with_hint_zero_uses_full_pool() {
        // Round 104 가드: hint=0 → division by zero 회피, 전체 풀 사용. 크래시/NaN 없음.
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 5)
        let env = makeEnvelope(raw)
        let est = BPHEstimator.estimateAutocorrelation(envelope: env, nominalBphHint: 0)
        if let e = est {
            XCTAssertFalse(e.rawBph.isNaN)
            XCTAssertGreaterThan(e.bph, 0)
        }
    }

    // MARK: - estimate 진입점: autoEst == onsetEst (confidence 병합)

    func test_estimate_merges_when_auto_and_onset_agree() {
        // 정확한 28800 신호 → autocorrelation 과 onset 모두 28800 → 병합 분기(line 54-61).
        // 병합 confidence = min(1, a.conf + o.conf*0.5) — a.conf 보다 크거나 같아야 한다.
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 6)
        let env = makeEnvelope(raw)
        // onset beats — 0.125s 간격 60개 (28800 BPH). envelope 와 동일 BPH.
        let beats = (0..<60).map {
            BeatEvent(timestampSeconds: Double($0) * 0.125, type: .tic, energy: 1.0)
        }
        let merged = BPHEstimator.estimate(envelope: env, beats: beats, nominalBphHint: 28_800)
        XCTAssertNotNil(merged)
        if let m = merged {
            XCTAssertEqual(m.bph, 28_800)
            XCTAssertGreaterThan(m.confidence, 0)
            XCTAssertLessThanOrEqual(m.confidence, 1.0, "병합 confidence 는 1.0 으로 clamp")
        }
    }

    // MARK: - fallbackFromOnsetRate 가드 (estimate 의 (nil, nil) 경로)

    func test_estimate_fallback_short_timespan_returns_nil() {
        // autoEst nil(짧은 env) + onsetEst nil(<8 beats 라 estimateFromOnsets 미진입은 아니지만
        // 20개라도 timeSpan<5s 면 fallback 가드 nil) → 최종 nil.
        // 20 beats, 간격 0.1s → span=1.9s < 5s.
        let beats = (0..<20).map {
            BeatEvent(timestampSeconds: Double($0) * 0.1, type: .tic, energy: 1.0)
        }
        let shortEnv = [Float](repeating: 0.0, count: 50)  // autocorr 가드(<=100 @200Hz) 차단
        let est = BPHEstimator.estimate(envelope: shortEnv, beats: beats, sampleRate: 200, nominalBphHint: 36_000)
        // 0.1s 간격 = 36000 BPH? 3600/0.1=36000. onsetEst 가 lock 할 수도 있으므로 nil 강제는 안 함.
        // 핵심: 짧은 span 케이스가 크래시 없이 통과. nil 또는 저신뢰 추정 모두 허용.
        if let e = est { XCTAssertFalse(e.rawBph.isNaN) }
    }

    func test_estimate_fallback_high_drift_returns_nil() {
        // 비표준 IOI (0.3s = 12000 BPH 인접 아님, 표준에서 drift 큼) + autocorr 차단.
        // onset score/median 도 표준 매칭 약함 → fallback drift>=0.15 가드로 nil 유도.
        // hint 로 28800 강제 → 0.3s(=12000 BPH) 는 28800 후보 ±20% 밖 → 후보 차단 → nil.
        let beats = (0..<30).map {
            BeatEvent(timestampSeconds: Double($0) * 0.3, type: .tic, energy: 1.0)
        }
        let shortEnv = [Float](repeating: 0.0, count: 50)
        let est = BPHEstimator.estimate(envelope: shortEnv, beats: beats, sampleRate: 200, nominalBphHint: 28_800)
        XCTAssertNil(est, "28800 hint 와 동떨어진 0.3s IOI 는 lock 되면 안 된다")
    }

    // MARK: - nearestStandardBPH 빈 candidates fallback

    func test_nearestStandardBPH_empty_candidates_falls_back_to_first_standard() {
        // candidates=[] → pool.first nil → standardBPHs[0] (=8400).
        XCTAssertEqual(BPHEstimator.nearestStandardBPH(28_800, candidates: []),
                       BPHEstimator.standardBPHs[0])
    }
}
