import Accelerate
import Foundation

/// Round 170 (사용자 + 팀 + 전문가 토론 결과): tickIQ-style simplified pipeline.
///
/// 기존 chain: BP → Env → NoiseSupp → Flux → MatchedFilter → BeatDetector → PLL → IOI → OLS/TM
/// 새 chain:   BP → Hilbert env → MAD threshold → parabolic interp → median tight-3%
///
/// 이유 — Müller/Chen 전문가 패널:
/// - Spectral flux 는 5ms 시간 분해능 (200Hz) — rate ±1 s/d 정밀도엔 부적합
/// - NoiseSuppressor 는 정상 tic burst 까지 attenuate 위험
/// - Matched filter 의 template 학습 instability
/// - **Simple = robust**. tickIQ ±5 s/d 의 비결.
enum SimplifiedBeatDetector {

    /// Hilbert analytic signal magnitude — instantaneous envelope.
    /// FFT-based 1-pass. 48kHz × 30s = 1.44M samples → vDSP FFT ~30ms.
    static func hilbertEnvelope(samples: [Float], sampleRate: Double, lpfCutoffHz: Double = 500) -> [Float] {
        let n = samples.count
        guard n > 4 else { return [] }
        // FFT 길이 = 2^ceil(log2(n))
        let log2n = vDSP_Length(ceil(log2(Double(n))))
        let fftN = Int(1 << log2n)

        // Real → complex
        var real = samples + Array(repeating: Float(0), count: fftN - n)
        var imag = [Float](repeating: 0, count: fftN)

        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                // Hilbert filter: H[0] = 1, H[1..N/2-1] = 2, H[N/2] = 1, rest = 0
                // 양의 frequency 만 2배, 음의 frequency 0.
                var zero: Float = 0
                vDSP_vfill(&zero, imagPtr.baseAddress!.advanced(by: fftN/2 + 1), 1, vDSP_Length(fftN/2 - 1))
                vDSP_vfill(&zero, realPtr.baseAddress!.advanced(by: fftN/2 + 1), 1, vDSP_Length(fftN/2 - 1))
                var two: Float = 2
                vDSP_vsmul(realPtr.baseAddress!.advanced(by: 1), 1, &two, realPtr.baseAddress!.advanced(by: 1), 1, vDSP_Length(fftN/2 - 1))
                vDSP_vsmul(imagPtr.baseAddress!.advanced(by: 1), 1, &two, imagPtr.baseAddress!.advanced(by: 1), 1, vDSP_Length(fftN/2 - 1))
                vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(FFT_INVERSE))
                // Normalize (vDSP inverse 는 N 배 스케일 결과).
                var norm: Float = 1.0 / Float(fftN)
                vDSP_vsmul(realPtr.baseAddress!, 1, &norm, realPtr.baseAddress!, 1, vDSP_Length(fftN))
                vDSP_vsmul(imagPtr.baseAddress!, 1, &norm, imagPtr.baseAddress!, 1, vDSP_Length(fftN))
            }
        }

        // |analytic| = sqrt(real² + imag²)
        var envelope = [Float](repeating: 0, count: n)
        for i in 0..<n {
            envelope[i] = sqrt(real[i] * real[i] + imag[i] * imag[i])
        }
        // 1-pole LPF (RC).
        let dt = 1.0 / sampleRate
        let rc = 1.0 / (2 * .pi * lpfCutoffHz)
        let alpha = Float(dt / (rc + dt))
        var state: Float = 0
        for i in 0..<n {
            state = alpha * envelope[i] + (1 - alpha) * state
            envelope[i] = state
        }
        return envelope
    }

    /// MAD-based adaptive threshold + parabolic interpolation for sub-sample onset times.
    /// - refractoryMs: 검출 후 일정 시간 이내 추가 검출 차단 (sub-pulse 회피).
    /// - kMad: threshold = median + k × 1.4826 × MAD.
    static func detectOnsets(envelope: [Float], sampleRate: Double, refractoryMs: Double = 80, kMad: Float = 3.0) -> [Double] {
        guard envelope.count > 4 else { return [] }
        // Robust threshold via median + MAD
        let sorted = envelope.sorted()
        let median = sorted[sorted.count / 2]
        var absDev = [Float](repeating: 0, count: envelope.count)
        for i in 0..<envelope.count {
            absDev[i] = abs(envelope[i] - median)
        }
        absDev.sort()
        let mad = absDev[absDev.count / 2]
        let threshold = median + kMad * 1.4826 * mad

        let refractorySamples = Int(refractoryMs / 1000.0 * sampleRate)
        var onsets: [Double] = []
        var i = 1
        let n = envelope.count
        while i < n - 1 {
            // Local max above threshold.
            if envelope[i] > threshold && envelope[i] > envelope[i-1] && envelope[i] > envelope[i+1] {
                // Parabolic interpolation for sub-sample precision.
                let y0 = envelope[i-1]
                let y1 = envelope[i]
                let y2 = envelope[i+1]
                let denom = y0 - 2*y1 + y2
                var offset: Float = 0
                if abs(denom) > 1e-9 {
                    offset = 0.5 * (y0 - y2) / denom
                    offset = max(-1, min(1, offset))
                }
                let preciseT = (Double(i) + Double(offset)) / sampleRate
                onsets.append(preciseT)
                i += refractorySamples
            } else {
                i += 1
            }
        }
        return onsets
    }

    /// Median IOI from tight 3% filtered onsets. Returns BPH or nil if insufficient data.
    /// - nominalBph: expected BPH (예: 28800) — IOI tight 필터 기준점.
    static func rateFromOnsets(onsets: [Double], nominalBph: Int) -> (bph: Double, beatCount: Int, residualRMSSeconds: Double)? {
        guard onsets.count >= 8 else { return nil }
        let nominalIOI = 3600.0 / Double(nominalBph)
        var iois: [Double] = []
        for i in 1..<onsets.count {
            iois.append(onsets[i] - onsets[i-1])
        }
        // Tight 5% — sub-pulse 변동 흡수, sample-level outlier 만 제외.
        let tolerance = nominalIOI * 0.05
        let tight = iois.filter { abs($0 - nominalIOI) <= tolerance }
        guard tight.count >= 8 else { return nil }
        let sortedTight = tight.sorted()
        let medianIOI = sortedTight[sortedTight.count / 2]
        // RMS residual of tight IOIs (per-beat).
        let mean = tight.reduce(0, +) / Double(tight.count)
        let variance = tight.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(tight.count)
        let rms = variance.squareRoot()
        return (bph: 3600.0 / medianIOI, beatCount: onsets.count, residualRMSSeconds: rms)
    }
}
