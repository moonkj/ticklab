import Accelerate
import Foundation

/// 2nd-order Butterworth band-pass (1kHz~10kHz @ 48kHz). 직접 비퀴드 구현.
/// 시계 tic/toc 에너지가 1~10kHz에 집중되므로 그 외 영역을 잘라 SNR을 높인다.
final class BandPassFilter {
    private let coeffsLow: BiquadCoefficients   // high-pass 1kHz
    private let coeffsHigh: BiquadCoefficients  // low-pass 10kHz
    private var stateLow = BiquadState()
    private var stateHigh = BiquadState()

    init(sampleRate: Double = 48_000, lowCutoff: Double = 1_000, highCutoff: Double = 10_000) {
        self.coeffsLow = BiquadCoefficients.highPass(sampleRate: sampleRate, cutoff: lowCutoff, q: 0.707)
        self.coeffsHigh = BiquadCoefficients.lowPass(sampleRate: sampleRate, cutoff: highCutoff, q: 0.707)
    }

    func process(_ samples: [Float]) -> [Float] {
        let highPassed = stateLow.apply(coeffsLow, to: samples)
        return stateHigh.apply(coeffsHigh, to: highPassed)
    }

    func reset() {
        stateLow = BiquadState()
        stateHigh = BiquadState()
    }
}

/// Direct Form II Transposed biquad filter primitive.
struct BiquadCoefficients {
    let b0, b1, b2, a1, a2: Float

    static func highPass(sampleRate: Double, cutoff: Double, q: Double) -> BiquadCoefficients {
        let omega = 2 * .pi * cutoff / sampleRate
        let alpha = sin(omega) / (2 * q)
        let cosOmega = cos(omega)
        let b0 = (1 + cosOmega) / 2
        let b1 = -(1 + cosOmega)
        let b2 = (1 + cosOmega) / 2
        let a0 = 1 + alpha
        let a1 = -2 * cosOmega
        let a2 = 1 - alpha
        return .init(
            b0: Float(b0 / a0), b1: Float(b1 / a0), b2: Float(b2 / a0),
            a1: Float(a1 / a0), a2: Float(a2 / a0)
        )
    }

    static func lowPass(sampleRate: Double, cutoff: Double, q: Double) -> BiquadCoefficients {
        let omega = 2 * .pi * cutoff / sampleRate
        let alpha = sin(omega) / (2 * q)
        let cosOmega = cos(omega)
        let b0 = (1 - cosOmega) / 2
        let b1 = 1 - cosOmega
        let b2 = (1 - cosOmega) / 2
        let a0 = 1 + alpha
        let a1 = -2 * cosOmega
        let a2 = 1 - alpha
        return .init(
            b0: Float(b0 / a0), b1: Float(b1 / a0), b2: Float(b2 / a0),
            a1: Float(a1 / a0), a2: Float(a2 / a0)
        )
    }
}

struct BiquadState {
    var z1: Float = 0
    var z2: Float = 0

    mutating func apply(_ c: BiquadCoefficients, to samples: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            let x = samples[i]
            let y = c.b0 * x + z1
            z1 = c.b1 * x - c.a1 * y + z2
            z2 = c.b2 * x - c.a2 * y
            out[i] = y
        }
        return out
    }
}
