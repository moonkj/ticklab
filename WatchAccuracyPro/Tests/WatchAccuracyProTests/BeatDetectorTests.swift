import XCTest
@testable import WatchAccuracyPro

final class BeatDetectorTests: XCTestCase {
    func test_detects_8_onsets_per_second_at_28800bph() {
        let durationSec: Double = 5
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: durationSec)
        let envelope = makeEnvelope(raw)
        let events = BeatDetector.detectOnsets(envelope: envelope)

        // 28800 BPH = 8 beats/sec. 5초 → 약 40 events. 시작/종료 buffer로 38~42 허용.
        XCTAssertGreaterThanOrEqual(events.count, 38)
        XCTAssertLessThanOrEqual(events.count, 42)
    }

    func test_alternates_tic_and_toc() {
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 2)
        let envelope = makeEnvelope(raw)
        let events = BeatDetector.detectOnsets(envelope: envelope)
        guard events.count >= 4 else {
            return XCTFail("이벤트가 너무 적음: \(events.count)")
        }
        for i in 0..<events.count - 1 {
            XCTAssertNotEqual(events[i].type, events[i + 1].type, "tic/toc 가 번갈아 나와야 한다")
        }
    }

    func test_returns_empty_for_silent_signal() {
        let env = [Float](repeating: 0.0001, count: 48_000)
        let events = BeatDetector.detectOnsets(envelope: env)
        XCTAssertTrue(events.isEmpty)
    }

    func test_inter_onset_intervals_match_bph() {
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 3)
        let envelope = makeEnvelope(raw)
        let events = BeatDetector.detectOnsets(envelope: envelope)
        guard events.count > 8 else { return XCTFail() }
        // 28800 BPH → inter-onset 0.125s. 시작 부근 transient 제외, 4번째 이후 평균.
        var diffs: [Double] = []
        for i in 4..<events.count {
            diffs.append(events[i].timestampSeconds - events[i - 1].timestampSeconds)
        }
        let mean = diffs.reduce(0, +) / Double(diffs.count)
        XCTAssertEqual(mean, 0.125, accuracy: 0.005)
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
