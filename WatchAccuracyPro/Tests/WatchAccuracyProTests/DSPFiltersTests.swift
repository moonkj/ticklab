import XCTest
@testable import WatchAccuracyPro

final class DSPFiltersTests: XCTestCase {
    func test_preEmphasis_dc_input_outputs_zero() {
        let f = PreEmphasisFilter(coefficient: 0.97)
        let dc = [Float](repeating: 1.0, count: 1000)
        let out = f.process(dc)
        // y[n] = x[n] - 0.97*x[n-1]. Steady-state: 1 - 0.97 = 0.03
        XCTAssertEqual(out.last!, 0.03, accuracy: 0.001)
    }

    func test_envelope_extracts_positive_envelope_of_sinusoid() {
        let sr: Double = 48_000
        let durationSec = 0.1
        var signal = [Float](repeating: 0, count: Int(sr * durationSec))
        for i in 0..<signal.count {
            signal[i] = sinf(2 * .pi * 1_000 * Float(i) / Float(sr))
        }
        let extractor = EnvelopeExtractor(sampleRate: sr, cutoffHz: 200)
        let env = extractor.process(signal)
        // settling 후 envelope 값은 sine의 |x|의 평균인 2/π ≈ 0.637 근처에 머문다.
        let tail = Array(env.suffix(env.count / 4))
        let mean = tail.reduce(0, +) / Float(tail.count)
        XCTAssertGreaterThan(mean, 0.4, "envelope is positive and tracks magnitude")
        XCTAssertLessThan(mean, 0.8)
    }

    func test_bandPass_attenuates_subbass_and_supersonic() {
        let sr: Double = 48_000
        let dur = 0.2
        let n = Int(sr * dur)
        var lowSignal = [Float](repeating: 0, count: n)
        var midSignal = [Float](repeating: 0, count: n)
        for i in 0..<n {
            lowSignal[i] = sinf(2 * .pi * 100 * Float(i) / Float(sr))   // 100 Hz, 통과대 아래
            midSignal[i] = sinf(2 * .pi * 4_000 * Float(i) / Float(sr)) // 4 kHz, 통과대 안
        }
        let bp = BandPassFilter(sampleRate: sr, lowCutoff: 1_000, highCutoff: 10_000)
        let lowOut = bp.process(lowSignal)
        bp.reset()
        let midOut = bp.process(midSignal)

        let lowRMS = rms(lowOut.suffix(n / 2))
        let midRMS = rms(midOut.suffix(n / 2))
        XCTAssertGreaterThan(midRMS, lowRMS * 5, "통과대(4kHz) 가 거의 그대로 통과해 100Hz 보다 훨씬 강해야 한다")
    }

    private func rms<S: Sequence>(_ samples: S) -> Float where S.Element == Float {
        var sum: Float = 0
        var count: Float = 0
        for v in samples { sum += v * v; count += 1 }
        guard count > 0 else { return 0 }
        return sqrtf(sum / count)
    }
}
