import Foundation

struct ConfidenceInputs {
    let snrDB: Double
    let durationSeconds: Double
    let bphAutocorrelationConfidence: Double  // 0~1, R(τ*)/R(0)
    let beatCount: Int
    let beatErrorMs: Double?
}

/// 측정 신뢰도(0~100)를 산출.
/// Master Plan Part 8.2 가중치 합산:
///   - SNR(dB) > 30 → 30, 20~30 → 20, <20 → 0
///   - 측정 시간 ≥120s → 25, ≥60s → 15, ≥30s → 10, <30s → 0
///   - BPH autocorrelation 신뢰도 → 25 × confidence
///   - tic/toc 분리도 (beat error 0~1ms 매핑) → 20 × (1 - clip01(beatError/2))
enum ConfidenceScorer {
    static func score(_ inputs: ConfidenceInputs) -> Int {
        var s = 0.0

        // SNR
        if inputs.snrDB >= 30 {
            s += 30
        } else if inputs.snrDB >= 20 {
            s += 20
        }

        // Duration
        if inputs.durationSeconds >= 120 {
            s += 25
        } else if inputs.durationSeconds >= 60 {
            s += 15
        } else if inputs.durationSeconds >= 30 {
            s += 10
        }

        // BPH autocorrelation confidence
        let bphConf = max(0, min(1, inputs.bphAutocorrelationConfidence))
        s += 25 * bphConf

        // tic/toc 분리도
        if let beatError = inputs.beatErrorMs {
            let normalized = max(0, min(1, beatError / 2.0))  // 2ms 이상이면 0점
            s += 20 * (1 - normalized)
        }

        return Int(s.rounded())
    }
}
