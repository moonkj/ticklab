import Accelerate
import Foundation

/// Round 158 (Wang Stanford CCRMA 권고): Multi-band envelope fusion.
///
/// 사용자 IWC IW371604 (Cal.35111 sapphire-back) 측정 실패 — single bandpass 가
/// frequency-dependent attenuation 에 취약. Sapphire case back 은 high-freq -10dB 감쇠
/// → 5-7kHz 만 보는 single BP 는 신호 못 잡음.
///
/// 해결: 3 octave-spaced bands 병렬 처리 + max fusion.
/// - Band 1: 1-3 kHz (low impulse / mechanical resonance)
/// - Band 2: 3-6 kHz (mid-frequency lock event)
/// - Band 3: 6-10 kHz (high impulse / drop event)
///
/// 각 band 별 envelope (abs + LPF) 계산 후 sample-wise max → 어느 band 든 신호 있으면 살아남음.
final class MultiBandEnvelope {
    private let bands: [(bp: BandPassFilter, env: EnvelopeExtractor)]

    init(sampleRate: Double = 48_000) {
        // Wang 권고: octave-spaced bands.
        let bandSpecs: [(low: Double, high: Double, envCutoff: Double)] = [
            (1_000, 3_000, 400),  // low: mechanical resonance
            (3_000, 6_000, 400),  // mid: lock event
            (6_000, 10_000, 400)  // high: impulse/drop
        ]
        self.bands = bandSpecs.map { spec in
            (
                bp: BandPassFilter(sampleRate: sampleRate, lowCutoff: spec.low, highCutoff: spec.high),
                env: EnvelopeExtractor(sampleRate: sampleRate, cutoffHz: spec.envCutoff)
            )
        }
    }

    /// 입력 raw audio → max-fused multi-band envelope.
    func process(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        // 각 band 별 envelope 계산.
        let envelopes: [[Float]] = bands.map { band in
            let bp = band.bp.process(samples)
            return band.env.process(bp)
        }
        // Sample-wise max fusion — 어느 band 든 강한 신호 있으면 살아남음.
        var fused = [Float](repeating: 0, count: samples.count)
        for env in envelopes {
            for i in 0..<min(env.count, fused.count) {
                if env[i] > fused[i] { fused[i] = env[i] }
            }
        }
        return fused
    }

    func reset() {
        bands.forEach { band in
            band.bp.reset()
            band.env.reset()
        }
    }
}
