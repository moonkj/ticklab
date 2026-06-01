import XCTest
@testable import WatchAccuracyPro

/// TemplateMatcher — self-learned template cross-correlation (순수 DSP, ModelContext/Vision 무관).
final class TemplateMatcherTests: XCTestCase {

    // MARK: - learn

    func test_learn_empty_onsets_yields_empty_template() {
        let matcher = TemplateMatcher(sampleRate: 1000, halfWindowMs: 10) // halfWindow = 10 samples
        let envelope = [Float](repeating: 1, count: 100)
        matcher.learn(envelope: envelope, onsets: [])
        XCTAssertTrue(matcher.template.isEmpty)
    }

    func test_learn_short_envelope_yields_empty_template() {
        let matcher = TemplateMatcher(sampleRate: 1000, halfWindowMs: 10) // halfWindow = 10 → needs > 20 samples
        let envelope = [Float](repeating: 1, count: 10) // 너무 짧음
        let onsets = [BeatEvent(timestampSeconds: 0.05, type: .tic, energy: 1.0)]
        matcher.learn(envelope: envelope, onsets: onsets)
        XCTAssertTrue(matcher.template.isEmpty)
    }

    func test_learn_all_onsets_out_of_bounds_yields_empty_template() {
        // halfWindow = 10. envelope 길이 100 (> 20 통과). 하지만 onset center 가 경계 밖이라 count==0.
        let matcher = TemplateMatcher(sampleRate: 1000, halfWindowMs: 10)
        let envelope = [Float](repeating: 1, count: 100)
        // centerIdx = 0.0 * 1000 = 0 → lo = -10 < 0 → skip. centerIdx=0.099*1000≈99 → hi=109 >= 100 → skip.
        let onsets = [
            BeatEvent(timestampSeconds: 0.0, type: .tic, energy: 1.0),
            BeatEvent(timestampSeconds: 0.099, type: .toc, energy: 1.0),
        ]
        matcher.learn(envelope: envelope, onsets: onsets)
        XCTAssertTrue(matcher.template.isEmpty)
    }

    func test_learn_produces_normalized_template_of_expected_length() {
        let matcher = TemplateMatcher(sampleRate: 1000, halfWindowMs: 10) // halfWindow = 10
        // 길이 200 envelope, onset 을 중앙(0.100s → idx 100)에 두어 [90...110] 윈도우 유효.
        var envelope = [Float](repeating: 0, count: 200)
        // 윈도우 안에 의미있는 값을 넣어 0-벡터(norm 0) 회피.
        for i in 90...110 { envelope[i] = Float(i - 89) }
        let onsets = [BeatEvent(timestampSeconds: 0.100, type: .tic, energy: 1.0)]
        matcher.learn(envelope: envelope, onsets: onsets)

        // template 길이 = 2*halfWindow + 1 = 21.
        XCTAssertEqual(matcher.template.count, 21)
        // L2 norm == 1 (정규화).
        let sumSq = matcher.template.reduce(Float(0)) { $0 + $1 * $1 }
        XCTAssertEqual(sqrt(sumSq), 1.0, accuracy: 1e-4)
    }

    // MARK: - refinePeakTime

    func test_refinePeakTime_returns_expected_when_template_empty() {
        let matcher = TemplateMatcher(sampleRate: 1000, halfWindowMs: 10)
        // learn 호출 안 함 → template 비어있음 → expectedTime 그대로 반환.
        let envelope = [Float](repeating: 1, count: 200)
        let result = matcher.refinePeakTime(envelope: envelope, expectedTime: 0.1)
        XCTAssertEqual(result, 0.1, accuracy: 1e-9)
    }

    func test_refinePeakTime_returns_expected_when_envelope_empty() {
        let matcher = TemplateMatcher(sampleRate: 1000, halfWindowMs: 10)
        // template 학습.
        var trainEnv = [Float](repeating: 0, count: 200)
        for i in 90...110 { trainEnv[i] = Float(i - 89) }
        matcher.learn(envelope: trainEnv, onsets: [BeatEvent(timestampSeconds: 0.100, type: .tic, energy: 1.0)])
        XCTAssertFalse(matcher.template.isEmpty)

        let result = matcher.refinePeakTime(envelope: [], expectedTime: 0.42)
        XCTAssertEqual(result, 0.42, accuracy: 1e-9)
    }

    func test_refinePeakTime_locks_onto_matching_pattern() {
        let matcher = TemplateMatcher(sampleRate: 1000, halfWindowMs: 10) // halfWindow=10, window len 21
        // 1) 뚜렷한 삼각형 펄스를 idx 100 중심으로 만들어 학습.
        var trainEnv = [Float](repeating: 0, count: 400)
        func placePulse(into arr: inout [Float], center: Int) {
            for off in -10...10 {
                arr[center + off] = Float(11 - abs(off)) // 1..11..1 삼각형
            }
        }
        placePulse(into: &trainEnv, center: 100)
        matcher.learn(envelope: trainEnv, onsets: [BeatEvent(timestampSeconds: 0.100, type: .tic, energy: 1.0)])
        XCTAssertFalse(matcher.template.isEmpty)

        // 2) 실제 펄스를 idx 205 (= 0.205s) 에 두고, 약간 어긋난 예상시각 0.200s 로 refine.
        var testEnv = [Float](repeating: 0, count: 400)
        placePulse(into: &testEnv, center: 205)
        let refined = matcher.refinePeakTime(envelope: testEnv, expectedTime: 0.200, searchWindowMs: 30)

        // 실제 피크(0.205s) 근처로 보정되어야 한다 (±2ms 이내).
        XCTAssertEqual(refined, 0.205, accuracy: 0.002)
    }
}
