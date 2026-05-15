import Accelerate
import Foundation

/// Round 158: tickIQ output 분석 (raw RMS -73dB → filtered RMS -93dB, crest 2.6 → 9.5) 기반.
/// time-domain noise floor subtraction + transient emphasis.
///
/// 동작:
/// 1. Slow running mean (baseline) — long time constant LPF (예: 50ms RC)
/// 2. Signal - baseline → centered (DC-free, baseline-free)
/// 3. Half-wave rectification (양수만 유지 — tic 가 baseline 위로 솟은 부분만)
/// 4. Soft knee — sub-noise 영역 zero out
///
/// 결과: tic transient 만 살아남는 sparse signal. Autocorrelation 자가상관 peak 강화.
final class NoiseFloorSuppressor {
    private let sampleRate: Double
    private let baselineAlpha: Float  // slow LPF
    private let envelopeAlpha: Float  // fast envelope LPF (abs follower)
    private var baselineState: Float = 0
    private var envelopeState: Float = 0
    /// Adaptive noise floor estimate — 매우 느린 LPF (5초 시정수).
    private var noiseFloorState: Float = 0
    private let noiseFloorAlpha: Float

    /// `baselineCutoffHz`: baseline tracker cutoff (10-50Hz 권장).
    /// `gateRatio`: 신호가 baseline 의 몇 배 이상이어야 통과 (1.5-3.0 권장).
    let gateRatio: Float

    init(sampleRate: Double = 48_000,
         baselineCutoffHz: Double = 20,
         envelopeCutoffHz: Double = 400,
         gateRatio: Float = 1.5) {
        self.sampleRate = sampleRate
        self.gateRatio = gateRatio
        let dt = 1.0 / sampleRate
        // Baseline tracker — slow.
        let rcBaseline = 1.0 / (2.0 * .pi * baselineCutoffHz)
        self.baselineAlpha = Float(dt / (rcBaseline + dt))
        // Envelope follower — fast.
        let rcEnvelope = 1.0 / (2.0 * .pi * envelopeCutoffHz)
        self.envelopeAlpha = Float(dt / (rcEnvelope + dt))
        // Noise floor — very slow (5s time constant).
        let rcNoise = 5.0
        self.noiseFloorAlpha = Float(dt / (rcNoise + dt))
    }

    /// raw audio (bandpass 후) → noise-suppressed envelope.
    func process(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        // Step 1: abs (rectified).
        var abs = [Float](repeating: 0, count: samples.count)
        vDSP.absolute(samples, result: &abs)
        // Step 2: fast envelope (sharp peak preserve).
        var envelope = [Float](repeating: 0, count: samples.count)
        var envState = envelopeState
        for i in 0..<abs.count {
            envState = envelopeAlpha * abs[i] + (1 - envelopeAlpha) * envState
            envelope[i] = envState
        }
        envelopeState = envState
        // Step 3: slow baseline tracker (background noise level).
        var baseline = [Float](repeating: 0, count: samples.count)
        var baseState = baselineState
        for i in 0..<envelope.count {
            baseState = baselineAlpha * envelope[i] + (1 - baselineAlpha) * baseState
            baseline[i] = baseState
        }
        baselineState = baseState
        // Step 4: noise floor estimate (very slow, captures sustained noise).
        var noiseFloor = noiseFloorState
        for v in baseline {
            noiseFloor = noiseFloorAlpha * v + (1 - noiseFloorAlpha) * noiseFloor
        }
        noiseFloorState = noiseFloor
        // Step 5: subtract baseline, gate with ratio, half-wave rectify.
        // y[n] = max(0, envelope[n] - baseline[n] × gateRatio).
        var out = [Float](repeating: 0, count: samples.count)
        for i in 0..<envelope.count {
            let threshold = baseline[i] * gateRatio
            let above = envelope[i] - threshold
            out[i] = above > 0 ? above : 0
        }
        return out
    }

    func reset() {
        baselineState = 0
        envelopeState = 0
        noiseFloorState = 0
    }
}
