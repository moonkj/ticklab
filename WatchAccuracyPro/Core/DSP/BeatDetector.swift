import Accelerate
import Foundation

enum BeatType: String, Sendable {
    case tic
    case toc
}

struct BeatEvent: Equatable, Sendable {
    /// 신호 시작 시각 기준 onset 위치 (초).
    let timestampSeconds: Double
    let type: BeatType
    /// envelope peak 값 (정규화 X) — confidence/amplitude 계산에 활용.
    let energy: Double
}

/// envelope에서 onset을 추출해 tic/toc parity를 부여한다.
enum BeatDetector {
    static func detectOnsets(
        envelope: [Float],
        sampleRate: Double = 48_000,
        thresholdK: Float = 4.0,
        refractoryMs: Double = 30.0
    ) -> [BeatEvent] {
        guard envelope.count > 0 else { return [] }
        var mean: Float = 0
        var stddev: Float = 0
        vDSP_normalize(envelope, 1, nil, 1, &mean, &stddev, vDSP_Length(envelope.count))
        let threshold = mean + thresholdK * stddev

        let refractorySamples = Int(refractoryMs / 1_000 * sampleRate)
        var onsets: [(idx: Int, energy: Float)] = []
        var i = 1
        while i < envelope.count - 1 {
            let v = envelope[i]
            if v >= threshold && v >= envelope[i - 1] && v >= envelope[i + 1] {
                onsets.append((i, v))
                i += refractorySamples
            } else {
                i += 1
            }
        }

        // tic/toc parity 부여
        var events: [BeatEvent] = []
        events.reserveCapacity(onsets.count)
        for (idx, onset) in onsets.enumerated() {
            let type: BeatType = idx.isMultiple(of: 2) ? .tic : .toc
            events.append(BeatEvent(
                timestampSeconds: Double(onset.idx) / sampleRate,
                type: type,
                energy: Double(onset.energy)
            ))
        }
        return events
    }
}
