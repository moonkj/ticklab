import XCTest
@testable import WatchAccuracyPro

final class DSPPipelineLiveStreamTests: XCTestCase {
    func test_live_waveform_stream_emits_chunks_during_measurement() async throws {
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 2)
        let source = SyntheticAudioSource(signal: raw)
        let pipeline = DSPPipeline(
            source: source,
            nominalBph: 28_800,
            liftAngleDegrees: 52,
            escapement: .swissLever,
            reliabilityLabel: .high
        )

        // collect 시작 후 start()
        let stream = pipeline.liveWaveformStream
        let collectorTask = Task<[LiveWaveformChunk], Never> {
            var collected: [LiveWaveformChunk] = []
            for await chunk in stream {
                collected.append(chunk)
                if collected.count >= 3 { break }
            }
            return collected
        }
        try pipeline.start()
        _ = pipeline.stop()
        let chunks = await collectorTask.value
        XCTAssertGreaterThanOrEqual(chunks.count, 1, "최소 한 chunk 는 emit 돼야 한다")
        // peak-aware 다운샘플 → 모든 sample 은 [-1, 1] 범위
        for chunk in chunks {
            XCTAssertFalse(chunk.samples.isEmpty)
            XCTAssertLessThanOrEqual(chunk.samples.max() ?? 0, 1.0)
            XCTAssertGreaterThanOrEqual(chunk.samples.min() ?? 0, -1.0)
        }
    }

    func test_live_metrics_stream_throttles_to_at_most_one_per_500ms() async throws {
        // 5초 신호 → 0.5초 throttle 이라면 max ~10 emit
        let raw = SyntheticSignal.ticTocImpulseTrain(bph: 28_800, duration: 5)
        let source = SyntheticAudioSource(signal: raw)
        let pipeline = DSPPipeline(
            source: source,
            nominalBph: 28_800,
            liftAngleDegrees: 52,
            escapement: .swissLever,
            reliabilityLabel: .high
        )

        let stream = pipeline.liveMetricsStream
        let collectorTask = Task<Int, Never> {
            var n = 0
            for await _ in stream { n += 1 }
            return n
        }
        try pipeline.start()
        _ = pipeline.stop()
        let count = await collectorTask.value
        // SyntheticAudioSource 는 모든 chunk 를 즉시 흘리므로 wallclock 은 거의 0초.
        // throttle 이 정확히 동작하면 lastEmitTime 비교로 최대 1개만 emit (또는 0개).
        XCTAssertLessThanOrEqual(count, 2, "lastEmitTime throttle 로 burst emit 방지")
    }
}
