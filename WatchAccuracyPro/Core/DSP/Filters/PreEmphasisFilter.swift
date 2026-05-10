import Foundation

/// 1차 high-pass pre-emphasis: y[n] = x[n] - a*x[n-1]
/// `coefficient` 0.95 정도면 ~1kHz 위 주파수 +6dB/oct 부스트.
/// stateful 한 이유: 청크 경계에서도 연속성을 유지해야 하기 때문.
final class PreEmphasisFilter {
    private let coefficient: Float
    private var lastSample: Float = 0

    init(coefficient: Float = 0.97) {
        self.coefficient = coefficient
    }

    func process(_ samples: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: samples.count)
        var prev = lastSample
        for i in 0..<samples.count {
            let x = samples[i]
            out[i] = x - coefficient * prev
            prev = x
        }
        lastSample = prev
        return out
    }

    func reset() { lastSample = 0 }
}
