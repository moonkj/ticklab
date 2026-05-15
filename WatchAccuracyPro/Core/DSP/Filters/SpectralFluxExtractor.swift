import Accelerate
import Foundation

/// Spectral-flux-style transient detector (Audit 4 권고로 도입).
///
/// 기존 abs + IIR LP envelope 가 watch tic 의 sharp onset (~0.5-1ms) 을 1.6ms 시상수로 평탄화하여
/// autocorrelation/onset detection 둘 다 실패하던 문제 근본 해결.
///
/// 알고리즘:
/// 1. BandPass (1-7kHz) 후 신호를 5ms (240 samples @ 48kHz) 비중첩 윈도우로 chunk
/// 2. 각 윈도우의 RMS energy 계산
/// 3. **Half-wave rectified diff** = max(0, energy[t] - energy[t-1])
/// 4. 출력: 200 Hz rate 의 transient 신호 (rising edge 만 강조)
///
/// FFT 없이도 spectral flux 의 핵심 효과 (transient onset 보존) 달성.
/// 출력은 watch tic 마다 sharp peak 가 있고 그 사이는 거의 0 인 신호 → BPH lock 매우 쉬움.
final class SpectralFluxExtractor {
    /// 5ms hop @ 48kHz = 240 샘플. 출력 sampleRate = 200 Hz.
    static let frameSize = 240
    static let outputSampleRate: Double = 200.0

    private var prevEnergy: Float = 0
    private var carry: [Float] = []

    /// BandPass 후 raw 샘플을 입력. 출력: 200 Hz flux 시계열 (frame 별 1 샘플).
    func process(_ samples: [Float]) -> [Float] {
        var combined = carry
        combined.append(contentsOf: samples)
        var flux: [Float] = []
        var i = 0
        let n = combined.count
        while i + Self.frameSize <= n {
            var ms: Float = 0
            // RMS — vDSP 가속 (제곱합 / N → sqrt)
            combined.withUnsafeBufferPointer { ptr in
                let base = ptr.baseAddress!.advanced(by: i)
                vDSP_svesq(base, 1, &ms, vDSP_Length(Self.frameSize))
            }
            let energy = sqrt(ms / Float(Self.frameSize))
            let f = Swift.max(0, energy - prevEnergy)
            flux.append(f)
            prevEnergy = energy
            i += Self.frameSize
        }
        // 남은 샘플은 다음 chunk 와 합쳐 처리.
        if i < n {
            carry = Array(combined[i..<n])
        } else {
            carry.removeAll(keepingCapacity: true)
        }
        return flux
    }

    func reset() {
        prevEnergy = 0
        carry.removeAll(keepingCapacity: true)
    }
}
