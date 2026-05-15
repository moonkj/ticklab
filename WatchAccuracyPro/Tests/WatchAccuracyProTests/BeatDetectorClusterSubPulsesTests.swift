import XCTest
@testable import WatchAccuracyPro

/// Round 156: `BeatDetector.clusterSubPulses(beats:nominalBph:)` 단위 테스트.
///
/// 검증 항목:
/// - guard 분기 (nil/0/음수 BPH, beats.count < 2)
/// - clusterThreshold = expectedIOI × 0.30 동작
/// - maxGroupSpan = expectedIOI × 0.50 가드 (Min #1 fix)
/// - energy-weighted centroid timestamp 통합
/// - max energy 채택
/// - 통합 후 tic/toc parity 재할당
final class BeatDetectorClusterSubPulsesTests: XCTestCase {

    // MARK: - Guard 분기

    func test_nilNominalBph_returnsIdentity() {
        let beats: [BeatEvent] = [
            BeatEvent(timestampSeconds: 0.100, type: .tic, energy: 1.0),
            BeatEvent(timestampSeconds: 0.102, type: .toc, energy: 0.8),
        ]
        let result = BeatDetector.clusterSubPulses(beats: beats, nominalBph: nil)
        XCTAssertEqual(result, beats, "nil BPH → identity 반환")
    }

    func test_zeroNominalBph_returnsIdentity() {
        let beats: [BeatEvent] = [
            BeatEvent(timestampSeconds: 0.100, type: .tic, energy: 1.0),
            BeatEvent(timestampSeconds: 0.102, type: .toc, energy: 0.8),
        ]
        let result = BeatDetector.clusterSubPulses(beats: beats, nominalBph: 0)
        XCTAssertEqual(result, beats, "0 BPH → identity 반환")
    }

    func test_negativeNominalBph_returnsIdentity() {
        let beats: [BeatEvent] = [
            BeatEvent(timestampSeconds: 0.100, type: .tic, energy: 1.0),
            BeatEvent(timestampSeconds: 0.102, type: .toc, energy: 0.8),
        ]
        let result = BeatDetector.clusterSubPulses(beats: beats, nominalBph: -28_800)
        XCTAssertEqual(result, beats, "음수 BPH → identity 반환")
    }

    func test_emptyBeats_returnsEmpty() {
        let result = BeatDetector.clusterSubPulses(beats: [], nominalBph: 28_800)
        XCTAssertTrue(result.isEmpty, "빈 입력 → 빈 출력")
    }

    func test_singleBeat_returnsSameSingle() {
        let beats = [BeatEvent(timestampSeconds: 0.1, type: .tic, energy: 1.0)]
        let result = BeatDetector.clusterSubPulses(beats: beats, nominalBph: 28_800)
        XCTAssertEqual(result, beats, "1개 입력 → 그대로 반환")
    }

    // MARK: - 정상 sequence (cluster 없음)

    func test_28800bph_normalSequence_noClustering() {
        // 28800 BPH → IOI 0.125s. gap 0.125s 는 threshold(0.0375s) 밖 → cluster 없음.
        // 입력 parity 와 index 기반 재할당 parity 가 동일하므로 입출력 동일해야 함.
        let beats: [BeatEvent] = (0..<8).map { i in
            BeatEvent(
                timestampSeconds: Double(i) * 0.125,
                type: i.isMultiple(of: 2) ? .tic : .toc,
                energy: 1.0
            )
        }
        let result = BeatDetector.clusterSubPulses(beats: beats, nominalBph: 28_800)
        XCTAssertEqual(result.count, beats.count, "cluster 없음 → 개수 보존")
        for (idx, ev) in result.enumerated() {
            XCTAssertEqual(ev.timestampSeconds, beats[idx].timestampSeconds, accuracy: 1e-9)
            XCTAssertEqual(ev.energy, beats[idx].energy, accuracy: 1e-9)
            // parity 재할당: idx 0,2,4,6 → tic, 1,3,5,7 → toc.
            let expected: BeatType = idx.isMultiple(of: 2) ? .tic : .toc
            XCTAssertEqual(ev.type, expected)
        }
    }

    // MARK: - sub-pulse 쌍 통합 (centroid)

    func test_28800bph_subPulsePair_mergedWithEnergyWeightedCentroid() {
        // 28800 BPH → IOI 125ms. gap 2ms 는 threshold(37.5ms) 안 → 통합.
        // energy: 1.0 (t=0.100), 3.0 (t=0.102). weighted centroid = (0.100×1 + 0.102×3)/4 = 0.4060/4 = 0.1015.
        // max energy = 3.0.
        let beats: [BeatEvent] = [
            BeatEvent(timestampSeconds: 0.100, type: .tic, energy: 1.0),
            BeatEvent(timestampSeconds: 0.102, type: .toc, energy: 3.0),
        ]
        let result = BeatDetector.clusterSubPulses(beats: beats, nominalBph: 28_800)
        XCTAssertEqual(result.count, 1, "쌍 통합 후 1개")
        XCTAssertEqual(result[0].timestampSeconds, 0.1015, accuracy: 1e-6, "energy-weighted centroid")
        XCTAssertEqual(result[0].energy, 3.0, accuracy: 1e-9, "max energy 채택")
        XCTAssertEqual(result[0].type, .tic, "단일 onset idx 0 → tic")
    }

    // MARK: - 3-stage cascade (span < maxGroupSpan)

    func test_28800bph_threeSubPulseCascade_mergedSingle() {
        // 3 sub-pulse: t = 0.100, 0.102, 0.104 (gap 2ms 각).
        // gap 2ms ≤ 37.5ms ✓, 누적 span 0→4ms ≤ 62.5ms ✓ → 모두 단일 그룹.
        // weighted centroid = (0.100×1 + 0.102×2 + 0.104×1)/4 = 0.408/4 = 0.102.
        let beats: [BeatEvent] = [
            BeatEvent(timestampSeconds: 0.100, type: .tic, energy: 1.0),
            BeatEvent(timestampSeconds: 0.102, type: .toc, energy: 2.0),
            BeatEvent(timestampSeconds: 0.104, type: .tic, energy: 1.0),
        ]
        let result = BeatDetector.clusterSubPulses(beats: beats, nominalBph: 28_800)
        XCTAssertEqual(result.count, 1, "3 sub-pulse cascade → 단일 onset")
        XCTAssertEqual(result[0].timestampSeconds, 0.102, accuracy: 1e-6)
        XCTAssertEqual(result[0].energy, 2.0, accuracy: 1e-9)
        XCTAssertEqual(result[0].type, .tic)
    }

    // MARK: - maxGroupSpan 가드 (Min #1 fix)

    func test_28800bph_groupSpanGuard_preventsGreedyChaining() {
        // 4 onset, gap 30ms 씩. 누적 span: 0, 30, 60, 90ms.
        // expectedIOI=125ms, threshold=37.5ms, maxGroupSpan=62.5ms.
        // i=0: gap(0→1)=30 ≤ 37.5 ✓, span=30 ≤ 62.5 ✓ → groupEnd=1.
        //      gap(1→2)=30 ≤ 37.5 ✓, span=60 ≤ 62.5 ✓ → groupEnd=2.
        //      gap(2→3)=30 ≤ 37.5 ✓, span=90 ≤ 62.5 ✗ → STOP.
        // 결과: [0,1,2] merge → 1개, [3] 단독 → 1개. 총 2 onset.
        let beats: [BeatEvent] = [
            BeatEvent(timestampSeconds: 0.000, type: .tic, energy: 1.0),
            BeatEvent(timestampSeconds: 0.030, type: .toc, energy: 1.0),
            BeatEvent(timestampSeconds: 0.060, type: .tic, energy: 1.0),
            BeatEvent(timestampSeconds: 0.090, type: .toc, energy: 1.0),
        ]
        let result = BeatDetector.clusterSubPulses(beats: beats, nominalBph: 28_800)
        XCTAssertEqual(result.count, 2, "group span guard → 정상 beat 흡수 방지")
        // 첫 그룹 centroid = (0 + 0.030 + 0.060)/3 = 0.030 (균등 energy).
        XCTAssertEqual(result[0].timestampSeconds, 0.030, accuracy: 1e-6)
        // 마지막 단독 onset.
        XCTAssertEqual(result[1].timestampSeconds, 0.090, accuracy: 1e-9)
    }

    // MARK: - 통합 후 parity 재할당

    func test_parityReassignedAfterClustering() {
        // 두 쌍의 sub-pulse → 4 → 2 onset 으로 축소. idx 0 → tic, idx 1 → toc.
        // 첫 그룹 (t=0.100, 0.102) 입력 parity: tic, toc → 첫 onset.type = tic (group 첫 beat type).
        // 둘째 그룹 (t=0.225, 0.227) 입력 parity: tic, toc → 첫 onset.type = tic.
        // 재할당 후: idx 0 → tic, idx 1 → toc.
        let beats: [BeatEvent] = [
            BeatEvent(timestampSeconds: 0.100, type: .tic, energy: 1.0),
            BeatEvent(timestampSeconds: 0.102, type: .toc, energy: 1.0),
            BeatEvent(timestampSeconds: 0.225, type: .tic, energy: 1.0),
            BeatEvent(timestampSeconds: 0.227, type: .toc, energy: 1.0),
        ]
        let result = BeatDetector.clusterSubPulses(beats: beats, nominalBph: 28_800)
        XCTAssertEqual(result.count, 2, "2 쌍 → 2 onset")
        XCTAssertEqual(result[0].type, .tic, "idx 0 → tic")
        XCTAssertEqual(result[1].type, .toc, "idx 1 → toc")
        XCTAssertEqual(result[0].timestampSeconds, 0.101, accuracy: 1e-6, "첫 그룹 centroid")
        XCTAssertEqual(result[1].timestampSeconds, 0.226, accuracy: 1e-6, "둘째 그룹 centroid")
    }

    // MARK: - 다른 BPH 에서 threshold 스케일링

    func test_18000bph_clusterThresholdScalesWithIOI() {
        // 18000 BPH → IOI 200ms. threshold = 60ms, maxGroupSpan = 100ms.
        // gap 50ms ≤ 60ms ✓, span 50ms ≤ 100ms ✓ → 통합.
        let beats: [BeatEvent] = [
            BeatEvent(timestampSeconds: 0.000, type: .tic, energy: 1.0),
            BeatEvent(timestampSeconds: 0.050, type: .toc, energy: 1.0),
        ]
        let result = BeatDetector.clusterSubPulses(beats: beats, nominalBph: 18_000)
        XCTAssertEqual(result.count, 1, "18000 BPH gap 50ms (threshold 60ms 안) → 통합")
        XCTAssertEqual(result[0].timestampSeconds, 0.025, accuracy: 1e-6)
    }

    func test_36000bph_clusterThresholdTighterAtHighBeat() {
        // 36000 BPH → IOI 100ms. threshold = 30ms, maxGroupSpan = 50ms.
        // gap 25ms ≤ 30ms ✓, span 25ms ≤ 50ms ✓ → 통합.
        let beats: [BeatEvent] = [
            BeatEvent(timestampSeconds: 0.000, type: .tic, energy: 1.0),
            BeatEvent(timestampSeconds: 0.025, type: .toc, energy: 1.0),
        ]
        let result = BeatDetector.clusterSubPulses(beats: beats, nominalBph: 36_000)
        XCTAssertEqual(result.count, 1, "36000 BPH gap 25ms (threshold 30ms 안) → 통합")
        XCTAssertEqual(result[0].timestampSeconds, 0.0125, accuracy: 1e-6)
    }

    // MARK: - gap 이 threshold 직전/직후 경계

    func test_28800bph_gapJustAboveThreshold_noMerge() {
        // gap 40ms > 37.5ms → cluster 안 됨.
        let beats: [BeatEvent] = [
            BeatEvent(timestampSeconds: 0.000, type: .tic, energy: 1.0),
            BeatEvent(timestampSeconds: 0.040, type: .toc, energy: 1.0),
        ]
        let result = BeatDetector.clusterSubPulses(beats: beats, nominalBph: 28_800)
        XCTAssertEqual(result.count, 2, "gap 40ms > 37.5ms → 분리 유지")
    }
}
