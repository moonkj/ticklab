import Foundation

/// 1차 high-pass pre-emphasis: y[n] = x[n] - a*x[n-1]
/// `coefficient` 0.95 정도면 ~1kHz 위 주파수 +6dB/oct 부스트.
/// stateful 한 이유: 청크 경계에서도 연속성을 유지해야 하기 때문.
///
/// 사용자 보고: "조용한 곳에서 핸드폰 붙였는데도 감지 못 함" — 0.97 은 24kHz 에서 +36dB
/// 부스트라 마이크 자체 잡음을 증폭하는 부작용. coefficient 0.0 이면 identity (skip).
/// 실 watch tic 은 1-8kHz 에 충분한 에너지가 있어 pre-emphasis 없이도 BandPass 로 충분히 잡힘.
final class PreEmphasisFilter {
    private let coefficient: Float
    private var lastSample: Float = 0

    // Round 130 (Chen P3 + Müller §3): 0.0 → 0.5. IWC 같은 케이스 댐핑 시계 고주파 tic 강조.
    // 0.5는 0.0(bypass)과 0.97(과대 noise) 절충. transient sharpness 우선.
    init(coefficient: Float = 0.5) {
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
