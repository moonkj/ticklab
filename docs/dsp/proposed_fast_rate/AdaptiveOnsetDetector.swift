import Foundation
import Accelerate

// MARK: - AdaptiveOnsetDetector
// 기존 BeatDetector(고정 threshold + 고정 30ms refractory)를 교체하는 제안.
//  1. Adaptive threshold = percentile75(최근 envelope) × 1.8 (환경 변화 적응)
//  2. Refractory = halfPeriod(BPH) × 0.85 (28800 BPH: 106ms, 18000: 170ms)
//  3. 청크 단위 시각 해상도 유지(50ms 청크 권장)
// (제안 — 미통합. 검토용 보관.)

final class AdaptiveOnsetDetector {

    // MARK: - Configuration
    private let thresholdFactor: Float = 1.8
    private let historyCapacity: Int
    let refractoryPeriod: Double
    let chunkDuration: Double

    // MARK: - State
    private var envelopeHistory: [Float] = []
    private(set) var lastOnsetTime: Double = -.infinity
    private var chunkIndex: Int = 0
    private(set) var beatParity: Int = 0

    // MARK: - Init
    /// - Parameters:
    ///   - bph: 측정 대상 무브먼트 BPH (MovementDB 또는 Goertzel 추정값).
    ///   - chunkDuration: 청크 길이 초 (AVAudioEngine tap buffer / sampleRate).
    init(bph: Int, chunkDuration: Double = 0.05) {
        self.chunkDuration = chunkDuration
        let halfPeriod = 3600.0 / Double(bph)
        self.refractoryPeriod = halfPeriod * 0.85
        let chunksPerFullPeriod = max(1, Int(halfPeriod * 2.0 / chunkDuration))
        self.historyCapacity = max(40, chunksPerFullPeriod * 10)
    }

    // MARK: - Processing
    /// 청크 하나의 envelope peak 값을 입력.
    /// - Returns: onset이 감지되면 해당 시각(초), 미감지 시 nil.
    @discardableResult
    func process(envelopePeak: Float) -> Double? {
        let t = Double(chunkIndex) * chunkDuration
        chunkIndex += 1

        envelopeHistory.append(envelopePeak)
        if envelopeHistory.count > historyCapacity {
            envelopeHistory.removeFirst()
        }
        guard envelopeHistory.count >= 15 else { return nil }

        let threshold = percentile75(envelopeHistory) * thresholdFactor
        guard envelopePeak > threshold else { return nil }
        guard t - lastOnsetTime > refractoryPeriod else { return nil }

        lastOnsetTime = t
        beatParity += 1
        return t
    }

    func reset() {
        envelopeHistory.removeAll()
        lastOnsetTime = -.infinity
        chunkIndex = 0
        beatParity = 0
    }

    // MARK: - Statistics helper
    private func percentile75(_ arr: [Float]) -> Float {
        guard !arr.isEmpty else { return 0 }
        var sorted = arr
        vDSP_vsort(&sorted, vDSP_Length(sorted.count), 1)
        let idx = min(Int(Float(sorted.count) * 0.75), sorted.count - 1)
        return sorted[idx]
    }
}
