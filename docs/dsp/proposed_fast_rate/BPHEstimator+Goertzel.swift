import Foundation
import Accelerate

// MARK: - BPHEstimator + Goertzel extension
// MovementDB에 BPH가 없는 캘리버용 빠른 BPH 추정. Full FFT 대신 O(N) Goertzel로
// 표준 BPH 6개만 검사. 1초 버퍼로 autocorrelation 10초와 동등 의도.
// (제안 — 미통합. 검토용 보관. ⚠️ targetHz = bph/7200 라벨 검증 필요 — 리뷰 포인트.)

extension BPHEstimator {

    static let standardBPHCandidates: [Int] = [18000, 19800, 21600, 25200, 28800, 36000]

    enum EstimationSource {
        case movementDB
        case goertzel
        case autocorrelation
    }

    struct GoertzelEstimate {
        let bph: Int
        let confidence: Double   // 0.0 ~ 1.0
        let source: EstimationSource
    }

    // MARK: - Fast estimate via Goertzel filter bank
    static func goertzelEstimate(
        envelopeSamples: [Float],
        sampleRate: Double = 48_000,
        minDuration: Double = 1.0
    ) -> GoertzelEstimate? {

        let minSamples = Int(sampleRate * minDuration)
        guard envelopeSamples.count >= minSamples else { return nil }

        let scores: [(bph: Int, energy: Double)] = standardBPHCandidates.map { bph in
            let halfBeatHz = Double(bph) / 7200.0
            let energy = goertzelEnergy(
                samples: envelopeSamples,
                targetHz: halfBeatHz,
                sampleRate: sampleRate
            )
            return (bph, energy)
        }

        let totalEnergy = scores.map(\.energy).reduce(0, +)
        guard totalEnergy > 0 else { return nil }

        let best = scores.max(by: { $0.energy < $1.energy })!
        let fraction = best.energy / totalEnergy
        guard fraction > 0.30 else { return nil }

        let confidence = min((fraction - 0.30) / 0.50, 1.0)
        return GoertzelEstimate(bph: best.bph, confidence: confidence, source: .goertzel)
    }

    static func knownBPHEstimate(_ bph: Int) -> GoertzelEstimate {
        GoertzelEstimate(bph: bph, confidence: 1.0, source: .movementDB)
    }

    // MARK: - Goertzel kernel (single frequency)
    private static func goertzelEnergy(
        samples: [Float],
        targetHz: Double,
        sampleRate: Double
    ) -> Double {
        let N = samples.count
        let normalizedFreq = targetHz / sampleRate
        let omega = 2.0 * Double.pi * normalizedFreq
        let coeff = Float(2.0 * cos(omega))

        var s1: Float = 0, s2: Float = 0
        for x in samples {
            let s0 = x + coeff * s1 - s2
            s2 = s1; s1 = s0
        }
        let real = Double(s1) - Double(s2) * cos(omega)
        let imag = Double(s2) * sin(omega)
        return (real * real + imag * imag) / Double(N * N)
    }
}
