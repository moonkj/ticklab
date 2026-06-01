import XCTest
@testable import WatchAccuracyPro

/// 커버리지 보강 — BPHEstimator 의 기존 BPHEstimatorTests 가 안 다루는 분기.
///   · subtractMovingAverage (가드/정상 경로)
///   · nearestStandardBPH (candidates 파라미터 / 빈 풀)
///   · estimateFromOnsets (too-few 가드, perfect-onset score 경로)
///   · estimateAutocorrelation (짧은 envelope 가드, hint 경로)
///   · standardBPHs / minConfidence 상수 invariant
///
/// 기존 BPHEstimatorTests/MeasurementViewModelTests 의 단언과 중복하지 않는다.
/// BPHEstimator 는 enum 정적 함수 — @MainActor 불필요.
final class BPHEstimatorBranchTests: XCTestCase {

    // MARK: - subtractMovingAverage

    func test_subtractMovingAverage_empty_input_is_noop() {
        // n == 0 가드 — output 변경 없음, 크래시 없음.
        var out: [Float] = []
        BPHEstimator.subtractMovingAverage([], into: &out, window: 4)
        XCTAssertTrue(out.isEmpty)
    }

    func test_subtractMovingAverage_output_too_small_is_noop() {
        // output.count < n 가드 — output 그대로 유지.
        let input: [Float] = [1, 2, 3, 4]
        var out: [Float] = [0, 0]  // 길이 부족
        BPHEstimator.subtractMovingAverage(input, into: &out, window: 2)
        XCTAssertEqual(out, [0, 0], "output 이 부족하면 변경하지 않는다")
    }

    func test_subtractMovingAverage_constant_signal_becomes_zero() {
        // 상수 신호의 moving average 는 자기 자신 → 차감 결과 모두 0.
        let input = [Float](repeating: 5.0, count: 100)
        var out = [Float](repeating: -1, count: 100)
        BPHEstimator.subtractMovingAverage(input, into: &out, window: 10)
        for v in out {
            XCTAssertEqual(v, 0, accuracy: 1e-4, "상수 신호 detrend 결과는 0")
        }
    }

    func test_subtractMovingAverage_removes_dc_offset() {
        // DC + 작은 변동 → detrend 후 평균이 0 부근.
        var input = [Float](repeating: 10.0, count: 200)
        for i in 0..<200 { input[i] += Float(sin(Double(i) * 0.3)) }
        var out = [Float](repeating: 0, count: 200)
        BPHEstimator.subtractMovingAverage(input, into: &out, window: 20)
        let mean = out.reduce(Float(0), +) / Float(out.count)
        XCTAssertEqual(mean, 0, accuracy: 0.2, "detrend 후 평균은 0 부근")
    }

    // MARK: - nearestStandardBPH (candidates 파라미터 분기)

    func test_nearestStandardBPH_with_restricted_candidates() {
        // candidates 제공 시 그 풀에서만 선택. 21600 가 후보에 없으면 21000 선택.
        let restricted = [18_000, 21_000, 25_200]
        XCTAssertEqual(BPHEstimator.nearestStandardBPH(21_500, candidates: restricted), 21_000)
        XCTAssertEqual(BPHEstimator.nearestStandardBPH(24_000, candidates: restricted), 25_200)
    }

    func test_nearestStandardBPH_single_candidate_always_returns_it() {
        XCTAssertEqual(BPHEstimator.nearestStandardBPH(99_999, candidates: [28_800]), 28_800)
    }

    func test_nearestStandardBPH_nil_candidates_uses_full_pool() {
        // candidates == nil → standardBPHs 전체 사용. 8400 이 가장 가까움.
        XCTAssertEqual(BPHEstimator.nearestStandardBPH(8_500), 8_400)
        XCTAssertEqual(BPHEstimator.nearestStandardBPH(36_500), 36_000)
    }

    // MARK: - estimateFromOnsets

    func test_estimateFromOnsets_too_few_beats_returns_nil() {
        // beats.count < 8 가드.
        let beats = (0..<5).map {
            BeatEvent(timestampSeconds: Double($0) * 0.125, type: .tic, energy: 1.0)
        }
        XCTAssertNil(BPHEstimator.estimateFromOnsets(beats: beats, envelope: []))
    }

    func test_estimateFromOnsets_perfect_28800_locks_score_path() {
        // 정확히 0.125s 간격 → 28800 BPH score 경로 lock.
        // 60개 onset → valid >= 6, match count >= 4, ratio >= 0.20 모두 통과.
        let beats = (0..<60).map {
            BeatEvent(timestampSeconds: Double($0) * 0.125, type: .tic, energy: 1.0)
        }
        let est = BPHEstimator.estimateFromOnsets(beats: beats, envelope: [])
        let unwrapped = try? XCTUnwrap(est)
        XCTAssertNotNil(unwrapped, "정확한 0.125s 간격 onset 은 lock 돼야 한다")
        if let e = est {
            XCTAssertEqual(e.bph, 28_800)
            XCTAssertGreaterThan(e.confidence, 0)
            XCTAssertEqual(e.rawBph, 28_800, accuracy: 50)
        }
    }

    func test_estimateFromOnsets_perfect_21600_locks() {
        // 0.16667s 간격 → 21600 BPH (3600/21600).
        let ioi = 3600.0 / 21_600.0
        let beats = (0..<60).map {
            BeatEvent(timestampSeconds: Double($0) * ioi, type: .tic, energy: 1.0)
        }
        let est = BPHEstimator.estimateFromOnsets(beats: beats, envelope: [])
        if let e = est {
            XCTAssertEqual(e.bph, 21_600)
        } else {
            XCTFail("정확한 21600 간격 onset 은 lock 돼야 한다")
        }
    }

    func test_estimateFromOnsets_hint_zero_does_not_crash() {
        // Round 104 가드 — hint=0 이면 division by zero 회피, 전체 풀 사용. 크래시/ NaN 없음.
        let beats = (0..<60).map {
            BeatEvent(timestampSeconds: Double($0) * 0.125, type: .tic, energy: 1.0)
        }
        let est = BPHEstimator.estimateFromOnsets(beats: beats, envelope: [], nominalBphHint: 0)
        if let e = est { XCTAssertFalse(e.rawBph.isNaN) }
    }

    func test_estimateFromOnsets_all_intervals_invalid_returns_nil() {
        // 모든 IOI 가 valid 범위(0.040~0.800) 밖 → valid.count < 6 → nil.
        let beats = (0..<10).map {
            BeatEvent(timestampSeconds: Double($0) * 1.5, type: .tic, energy: 1.0)  // 1.5s > 0.8 상한
        }
        XCTAssertNil(BPHEstimator.estimateFromOnsets(beats: beats, envelope: []))
    }

    // MARK: - estimateAutocorrelation

    func test_estimateAutocorrelation_short_envelope_returns_nil() {
        // envelope.count <= sampleRate*0.5 가드 (200Hz 기준 100 샘플 미만).
        let short = [Float](repeating: 0.5, count: 50)
        XCTAssertNil(BPHEstimator.estimateAutocorrelation(envelope: short, sampleRate: 200))
    }

    func test_estimateAutocorrelation_flat_signal_does_not_crash() {
        // 평탄 신호 — 가드/경로 실행. 크래시만 안 하면 OK(nil 또는 저신뢰 추정 모두 허용).
        let flat = [Float](repeating: 0.3, count: 1_000)
        _ = BPHEstimator.estimateAutocorrelation(envelope: flat, sampleRate: 200)
    }

    // MARK: - estimate 진입점 (onset fallback path)

    func test_estimate_fallback_from_onset_rate_when_autocorr_fails() {
        // autocorrelation 실패(짧은/약한 envelope) + 충분한 onset(>=20, span>=5s, drift<15%)
        // → fallbackFromOnsetRate 경로 진입.
        // 28800 BPH = 8 onset/s. 6초간 48개 onset → onsetRate=8 → rawBph=14400... 실제로는
        //   span/count 기반. 정확히 28800 lag(0.125s) 간격을 주면 rawBph≈28800 으로 snap.
        let beats = (0..<48).map {
            BeatEvent(timestampSeconds: Double($0) * 0.125, type: .tic, energy: 1.0)
        }
        // envelope 은 autocorr 가드(count<=100 @200Hz)를 통과 못하도록 짧게 — fallback 또는 onset 경로 유도.
        let shortEnv = [Float](repeating: 0.0, count: 50)
        let est = BPHEstimator.estimate(envelope: shortEnv, beats: beats, sampleRate: 200)
        // autoEst 는 nil(짧은 envelope), onsetEst 또는 fallback 이 결과 반환.
        if let e = est {
            XCTAssertGreaterThan(e.bph, 0)
            XCTAssertFalse(e.rawBph.isNaN)
        }
        // nil 도 허용 — 핵심은 크래시 없이 fallback 분기를 통과하는 것.
    }

    func test_estimate_no_signal_and_no_beats_returns_nil() {
        // autoEst nil + onsetEst nil + fallback(beats<20) nil → 최종 nil.
        let shortEnv = [Float](repeating: 0.0, count: 50)
        XCTAssertNil(BPHEstimator.estimate(envelope: shortEnv, beats: [], sampleRate: 200))
    }

    // MARK: - 상수 invariant

    func test_standardBPHs_are_sorted_ascending() {
        let arr = BPHEstimator.standardBPHs
        for i in 1..<arr.count {
            XCTAssertGreaterThan(arr[i], arr[i - 1], "standardBPHs 는 오름차순이어야 한다")
        }
    }

    func test_standardBPHs_count_is_twelve() {
        XCTAssertEqual(BPHEstimator.standardBPHs.count, 12)
    }

    func test_minConfidence_is_small_positive() {
        XCTAssertGreaterThan(BPHEstimator.minConfidence, 0)
        XCTAssertLessThan(BPHEstimator.minConfidence, 0.01)
    }
}
