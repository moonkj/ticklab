import XCTest
@testable import WatchAccuracyPro

/// PURE DSP 커버리지: NoiseSuppressor.suppress — window energy 기반 spike zero-out.
final class NoiseSuppressorTests: XCTestCase {

    private let sr = 48_000.0

    private func assertAllFinite(_ xs: [Float], _ msg: String = "") {
        for v in xs { XCTAssertTrue(v.isFinite, "non-finite 값 발견 \(msg)") }
    }

    // MARK: - guard / passthrough paths

    func test_empty_returnsEmpty() {
        XCTAssertEqual(NoiseSuppressor.suppress([], sampleRate: sr), [])
    }

    func test_fewerThanTwoWindows_passthrough() {
        // window 가 1개 이하면 그대로 반환 (numWindows >= 2 가드).
        let windowSamples = Int(20.0 / 1_000 * sr) // 960
        let signal = [Float](repeating: 1.0, count: windowSamples - 1)
        let out = NoiseSuppressor.suppress(signal, sampleRate: sr)
        XCTAssertEqual(out, signal)
    }

    func test_outputLengthMatchesInput() {
        let signal = (0..<10_000).map { Float(sin(Double($0) * 0.01)) }
        let out = NoiseSuppressor.suppress(signal, sampleRate: sr)
        XCTAssertEqual(out.count, signal.count)
        assertAllFinite(out)
    }

    // MARK: - silence

    func test_silenceStaysSilent() {
        // 전부 0 → median 0 → guard median > 0 으로 그대로 반환, 여전히 무음.
        let silence = [Float](repeating: 0, count: 20_000)
        let out = NoiseSuppressor.suppress(silence, sampleRate: sr)
        XCTAssertEqual(out.count, silence.count)
        XCTAssertTrue(out.allSatisfy { $0 == 0 }, "무음은 무음으로 유지되어야 함")
    }

    // MARK: - spike suppression

    func test_singleHugeSpikeWindowZeroedOut() {
        // 균일한 낮은 신호 + 한 윈도우에만 거대 spike. 해당 윈도우가 0 으로 억제되어야 함.
        let windowSamples = Int(20.0 / 1_000 * sr) // 960
        var signal = [Float](repeating: 0.01, count: windowSamples * 20)
        // 5번째 window (index 4) 전체를 큰 값으로.
        let spikeLo = windowSamples * 4
        let spikeHi = spikeLo + windowSamples
        for i in spikeLo..<spikeHi { signal[i] = 10.0 }

        let out = NoiseSuppressor.suppress(signal, sampleRate: sr, thresholdRatio: 4.0)
        XCTAssertEqual(out.count, signal.count)
        assertAllFinite(out)

        // spike window 는 0 으로 억제.
        for i in spikeLo..<spikeHi {
            XCTAssertEqual(out[i], 0, "spike window sample \(i) 가 억제되지 않음")
        }
        // 정상 window 는 보존.
        XCTAssertEqual(out[0], 0.01, accuracy: 1e-6)
        XCTAssertEqual(out[windowSamples * 19], 0.01, accuracy: 1e-6)
    }

    func test_uniformSignalNotSuppressed() {
        // 모든 window energy 동일 → threshold(median*4) 초과 없음 → 변화 없음.
        let signal = [Float](repeating: 0.5, count: 20_000)
        let out = NoiseSuppressor.suppress(signal, sampleRate: sr)
        XCTAssertEqual(out, signal)
    }

    func test_customWindowAndThreshold_doesNotCrash() {
        let signal = (0..<5_000).map { _ in Float.random(in: 0...1) }
        let out = NoiseSuppressor.suppress(signal, sampleRate: sr, windowMs: 10, thresholdRatio: 2.0)
        XCTAssertEqual(out.count, signal.count)
        assertAllFinite(out)
    }
}
