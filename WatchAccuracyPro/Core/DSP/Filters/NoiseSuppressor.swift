import Accelerate
import Foundation

/// Industry-standard 노이즈 억제 (vacaboja/tg `noise_suppressor` port).
///
/// 동작: envelope 를 N ms window 로 나눠 각 window 의 squared energy 계산. 매 0.5s 의
/// per-window max 들의 median 을 baseline noise 로 산정. 어떤 window 의 energy 가 그
/// baseline × threshold 초과면 그 window 의 전체 sample 을 0 으로 만듦.
///
/// 효과: 한 거대 spike (마이크 contact noise, 손가락 움직임, 도어 슬램 등) 가
/// envelope/flux 위에서 BPHEstimator 의 autocorr 와 BeatDetector 의 threshold 다 망치는 효과 차단.
/// 사용자 보고된 "거대 spike 1개로 onset 47/121/162 잘못 잡힘" 케이스 해결.
enum NoiseSuppressor {
    /// - Parameters:
    ///   - envelope: 입력 envelope (audio-rate 또는 decimated 둘 다 가능).
    ///   - sampleRate: envelope 의 sample rate.
    ///   - windowMs: energy 윈도우 크기 (기본 20ms — tg 와 동일).
    ///   - thresholdRatio: baseline 대비 몇 배 초과 시 zero out (기본 4.0 — tg 의 2.0 보다 관대,
    ///     iPhone mic 의 normal tic 변동성이 desktop mic 보다 큼).
    static func suppress(
        _ envelope: [Float],
        sampleRate: Double,
        windowMs: Double = 20,
        thresholdRatio: Float = 4.0
    ) -> [Float] {
        guard !envelope.isEmpty else { return envelope }
        let windowSamples = max(1, Int(windowMs / 1_000 * sampleRate))
        let numWindows = (envelope.count + windowSamples - 1) / windowSamples
        guard numWindows >= 2 else { return envelope }

        // 1) 각 window 의 squared energy 합 계산.
        var energies = [Float](repeating: 0, count: numWindows)
        for w in 0..<numWindows {
            let lo = w * windowSamples
            let hi = min(envelope.count, lo + windowSamples)
            var sum: Float = 0
            for i in lo..<hi {
                let v = envelope[i]
                sum += v * v
            }
            energies[w] = sum
        }

        // 2) Baseline = median of all window energies.
        //    (tg 는 매 0.5s 의 per-window max 의 median 사용. 우리는 단순화.)
        let sorted = energies.sorted()
        let median = sorted[sorted.count / 2]
        guard median > 0 else { return envelope }
        let threshold = median * thresholdRatio

        // 3) Threshold 초과 window 의 전체 sample 을 0 으로.
        var suppressed = envelope
        for w in 0..<numWindows where energies[w] > threshold {
            let lo = w * windowSamples
            let hi = min(suppressed.count, lo + windowSamples)
            for i in lo..<hi { suppressed[i] = 0 }
        }
        return suppressed
    }
}
