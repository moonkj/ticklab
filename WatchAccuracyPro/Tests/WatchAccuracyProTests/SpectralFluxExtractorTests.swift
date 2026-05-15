import XCTest
@testable import WatchAccuracyPro

final class SpectralFluxExtractorTests: XCTestCase {
    func test_output_rate_is_200hz_for_continuous_input() {
        // 1 sec of constant low-amplitude signal @ 48kHz = 48000 samples
        // Expected output: 48000 / 240 = 200 flux samples.
        let ext = SpectralFluxExtractor()
        let samples = [Float](repeating: 0.01, count: 48_000)
        let flux = ext.process(samples)
        XCTAssertEqual(flux.count, 200, "200Hz 출력 rate")
    }

    func test_chunk_boundary_carry_preserves_sample_count() {
        // 480 + 100 + 100 + ... samples (irregular chunks) → still 200Hz output total.
        let ext = SpectralFluxExtractor()
        let chunks: [[Float]] = [
            [Float](repeating: 0.01, count: 480),
            [Float](repeating: 0.01, count: 100),
            [Float](repeating: 0.01, count: 240),
            [Float](repeating: 0.01, count: 480)
        ]
        var totalFlux = 0
        for c in chunks { totalFlux += ext.process(c).count }
        let totalIn = chunks.map { $0.count }.reduce(0, +)
        // Total frames produced = totalIn / 240 (carry handles remainder).
        // 480+100+240+480 = 1300. 1300/240 = 5.41 → 5 frames.
        XCTAssertEqual(totalFlux, totalIn / 240,
                       "chunk 경계 carry 정확 — \(totalIn / 240) frames 기대, \(totalFlux) 실제")
    }

    func test_impulse_train_produces_peaks_at_correct_rate() {
        // 28800 BPH = 8 impulses/sec at 48kHz → impulses every 6000 samples (125ms).
        // After flux: peaks at frame indices 25, 50, 75, ... (200Hz × 0.125s = 25 frames)
        let ext = SpectralFluxExtractor()
        let durationSec = 2.0
        let sampleRate: Double = 48_000
        let totalSamples = Int(durationSec * sampleRate)
        var signal = [Float](repeating: 0, count: totalSamples)
        // 8 Hz impulse train — width 5ms each.
        let burstSamples = 240  // 5ms
        let periodSamples = 6_000  // 125ms
        var t = 0
        while t + burstSamples < totalSamples {
            for i in 0..<burstSamples { signal[t + i] = 0.5 }
            t += periodSamples
        }
        let flux = ext.process(signal)
        // 2 sec * 8 Hz = 16 impulses expected.
        // Each impulse should produce 1 flux peak.
        // Count peaks (local max > some fraction of overall peak).
        let maxFlux = flux.max() ?? 0
        let threshold = maxFlux * 0.3
        var peakCount = 0
        for i in 1..<(flux.count - 1) {
            if flux[i] > threshold && flux[i] >= flux[i - 1] && flux[i] >= flux[i + 1] {
                peakCount += 1
            }
        }
        XCTAssertGreaterThanOrEqual(peakCount, 12, "16 impulse 중 적어도 12개 flux peak — got \(peakCount)")
        XCTAssertLessThanOrEqual(peakCount, 20, "spurious peak 적어야 — got \(peakCount)")
    }

    func test_silence_produces_zero_flux() {
        let ext = SpectralFluxExtractor()
        let silence = [Float](repeating: 0, count: 4_800)
        let flux = ext.process(silence)
        XCTAssertEqual(flux.count, 20, "100ms = 20 frames")
        for f in flux {
            XCTAssertEqual(f, 0, accuracy: 1e-6, "silence 는 flux=0")
        }
    }

    func test_reset_clears_carry_and_prev_energy() {
        let ext = SpectralFluxExtractor()
        // Feed some signal
        _ = ext.process([Float](repeating: 0.5, count: 100))
        ext.reset()
        // 240 samples should be ONE frame now (no carry from before).
        let flux = ext.process([Float](repeating: 0.01, count: 240))
        XCTAssertEqual(flux.count, 1, "reset 후 240 samples = 1 frame")
    }
}
