import Accelerate
import Foundation

/// 2nd-order Butterworth band-pass (1kHz~10kHz @ 48kHz). 직접 비퀴드 구현.
/// 시계 tic/toc 에너지가 1~10kHz에 집중되므로 그 외 영역을 잘라 SNR을 높인다.
final class BandPassFilter {
    private let coeffsLow: BiquadCoefficients   // high-pass 1kHz
    private let coeffsHigh: BiquadCoefficients  // low-pass 10kHz
    private var stateLow = BiquadState()
    private var stateHigh = BiquadState()

    /// Round 37 (tickIQ 가 같은 환경 같은 순간 정확 lock — 우리 algorithm 결함 확정):
    /// 3-10kHz revert → **1-7kHz**. 시계마다 case 공명 다양 (1kHz 부터 10kHz 까지). 좁은 band 가 IWC
    /// 같은 일부 시계의 tic energy 차단했을 가능성. wider band 가 더 안전.
    // Round 130 (DSP 전문가 3명 합의): 1-7kHz → 2.5-7kHz 좁힘.
    // 1-2.5kHz 케이스 공명/HVAC hum 제거 → percentile noise floor 안정 → IWC 약 tic 검출률 ↑.
    init(sampleRate: Double = 48_000, lowCutoff: Double = 2_500, highCutoff: Double = 7_000) {
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

/// Round 153 (Kim+Chen+Müller 토론): caliber-adaptive BandPass + envelope cutoff spec.
/// MatchedFilterProfile.resolve(...) 와 동일 dispatch — single source of truth.
/// 28800 BPH swissLever 는 production default 와 동일 → 회귀 zero.
struct BandPassSpec {
    let lowHz: Double
    let highHz: Double
    let envCutoffHz: Double

    // Round 158 (tickIQ deep analysis): tickIQ filter 가 2-5kHz 영역 -50dB 제거, 8-15kHz 영역 보존/boost.
    // 우리 2.5-7kHz 는 tickIQ 가 *무시하는* 영역 통과시킴. 6-15kHz 로 이동 — high-freq tic transient 영역.
    static let `default` = BandPassSpec(lowHz: 6_000, highHz: 15_000, envCutoffHz: 500)

    static func spec(for profile: MatchedFilterProfile, escapement: Escapement) -> BandPassSpec {
        // co-axial: matched filter 는 bypass 지만 BP 는 wide-band 로 sub-pulse 보존.
        if escapement == .coAxial {
            return .init(lowHz: 2_000, highHz: 9_000, envCutoffHz: 400)
        }
        switch profile {
        case .bypass:                 return .default
        case .vintage18k:             return .init(lowHz: 1_500, highHz: 5_000, envCutoffHz: 250)
        case .swissLever21600:        return .init(lowHz: 2_000, highHz: 6_000, envCutoffHz: 300)
        case .swissLever28800Classic: return .default  // 현재 production 값과 동일 (회귀 zero).
        case .highBeat36000:          return .init(lowHz: 3_500, highHz: 8_000, envCutoffHz: 500)
        }
    }
}
