import Accelerate
import Foundation

struct BPHEstimate: Equatable {
    let bph: Int                 // 표준 BPH로 스냅된 값 (18000/19800/21600/25200/28800/36000)
    let rawBph: Double           // autocorrelation peak에서 직접 계산한 값
    let confidence: Double       // 0~1, R(τ*) / R(0)
    let peakLagSeconds: Double   // autocorrelation peak이 잡힌 lag (초)
}

/// envelope 신호에서 시계의 BPH(시간당 비트수)를 추정한다.
///
/// 알고리즘:
/// 1. envelope의 autocorrelation R(τ) 계산
/// 2. peak τ* 위치 탐색 (50~420ms 범위 — 36000bph의 한 주기 200ms 부터 18000bph 의 400ms 까지)
/// 3. peak이 inter-onset (1 beat) 인지 full-cycle (tic+toc) 인지 자동 판별:
///    - candidate₁ = 3600 / τ  (1 beat 가정)
///    - candidate₂ = 7200 / τ  (1 cycle 가정)
///    각각 가장 가까운 표준 BPH로 스냅한 뒤 더 가까운 쪽을 채택
/// 4. confidence = R(τ*)/R(0)
enum BPHEstimator {
    static let standardBPHs: [Int] = [18_000, 19_800, 21_600, 25_200, 28_800, 36_000]

    static func estimate(envelope: [Float], sampleRate: Double = 48_000) -> BPHEstimate? {
        guard envelope.count > Int(sampleRate * 0.5) else { return nil }

        // DC 제거
        var mean: Float = 0
        vDSP_meanv(envelope, 1, &mean, vDSP_Length(envelope.count))
        var centered = [Float](repeating: 0, count: envelope.count)
        var negMean = -mean
        vDSP_vsadd(envelope, 1, &negMean, &centered, 1, vDSP_Length(envelope.count))

        var r0: Float = 0
        vDSP_dotpr(centered, 1, centered, 1, &r0, vDSP_Length(centered.count))
        guard r0 > 0 else { return nil }

        let minLagSamples = max(1, Int(sampleRate * 0.05))   // 50ms
        let maxLagSamples = Int(sampleRate * 0.42)            // 420ms

        var rValues = [Float](repeating: 0, count: maxLagSamples - minLagSamples + 1)
        centered.withUnsafeBufferPointer { ptr in
            let base = ptr.baseAddress!
            for (idx, lag) in (minLagSamples...maxLagSamples).enumerated() {
                let count = envelope.count - lag
                guard count > 0 else { break }
                var r: Float = 0
                vDSP_dotpr(base, 1, base.advanced(by: lag), 1, &r, vDSP_Length(count))
                rValues[idx] = r
            }
        }

        // 최고 피크 lag 찾기 (전역 최대)
        var globalMaxIdx = 0
        var globalMaxR: Float = -.infinity
        for i in 0..<rValues.count where rValues[i] > globalMaxR {
            globalMaxR = rValues[i]
            globalMaxIdx = i
        }
        guard globalMaxR > 0 else { return nil }

        // 최단 유의미 peak = inter-onset 가설.
        // 글로벌 최대의 50% 이상이고 local maximum 인 가장 작은 lag을 찾는다.
        // 없으면 글로벌 최대를 그대로 inter-onset 으로 간주한다 (스프링 드라이브 등 1주기만 포착되는 경우).
        let signifThreshold = globalMaxR * 0.5
        var bestIdx = globalMaxIdx
        for i in 1..<(rValues.count - 1) {
            let v = rValues[i]
            if v > signifThreshold && v >= rValues[i - 1] && v >= rValues[i + 1] {
                bestIdx = i
                break
            }
        }
        let bestR = rValues[bestIdx]

        // parabolic interpolation
        let lagInt = bestIdx + minLagSamples
        let lagDouble: Double = {
            guard bestIdx > 0, bestIdx < rValues.count - 1 else { return Double(lagInt) }
            let yL = rValues[bestIdx - 1]
            let yR = rValues[bestIdx + 1]
            let denom = yL - 2 * bestR + yR
            let delta = denom != 0 ? 0.5 * (yL - yR) / denom : 0
            return Double(lagInt) + Double(delta)
        }()

        let periodSeconds = lagDouble / sampleRate
        guard periodSeconds > 0 else { return nil }

        // τ 가 inter-onset(beat 1개) 이라고 가정하고 BPH = 3600/τ
        let raw = 3_600.0 / periodSeconds
        let snapped = nearestStandardBPH(raw)
        let snapDist = abs(raw - Double(snapped)) / Double(snapped)
        let chosenBPH = snapDist < 0.015 ? snapped : Int(raw.rounded())
        let confidence = Double(bestR / r0)
        return BPHEstimate(
            bph: chosenBPH,
            rawBph: raw,
            confidence: confidence,
            peakLagSeconds: periodSeconds
        )
    }

    static func nearestStandardBPH(_ raw: Double) -> Int {
        var bestDiff = Double.infinity
        var bestBph = standardBPHs[0]
        for bph in standardBPHs {
            let d = abs(raw - Double(bph))
            if d < bestDiff {
                bestDiff = d
                bestBph = bph
            }
        }
        return bestBph
    }
}
