import Accelerate
import Foundation

/// 신호 진폭 envelope 추출 — abs() + 1차 IIR low-pass.
/// Hilbert transform 보다 간단하고 tic/toc 펄스 검출에는 충분하다.
final class EnvelopeExtractor {
    private let alpha: Float // smoothing factor
    private var state: Float = 0

    /// `cutoffHz` 가 envelope 의 시간상수를 결정.
    /// **Audit 권고**: 200Hz (τ 0.8ms) 가 5ms tic 을 14dB 평탄화. 350Hz (τ 0.45ms) 로 sharper peak 보존.
    init(sampleRate: Double = 48_000, cutoffHz: Double = 350) {
        let dt = 1.0 / sampleRate
        let rc = 1.0 / (2.0 * .pi * cutoffHz)
        self.alpha = Float(dt / (rc + dt))
    }

    func process(_ samples: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: samples.count)
        // 절댓값 (벡터화)
        var abs = [Float](repeating: 0, count: samples.count)
        vDSP.absolute(samples, result: &abs)
        // 1-pole IIR low-pass: y[n] = a*x[n] + (1-a)*y[n-1]
        var prev = state
        for i in 0..<abs.count {
            prev = alpha * abs[i] + (1 - alpha) * prev
            out[i] = prev
        }
        state = prev
        return out
    }

    func reset() { state = 0 }
}
