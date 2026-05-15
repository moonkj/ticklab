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
    /// Percentile 기반 절대 임계 — 균형점 튜닝.
    /// 사용자 보고: 0.65/3.0 너무 엄격해 SNR 8dB (ratio 2.5) 에서 모든 tic 거부 → onsets 0.
    /// **0.55/1.8 로 완화** — marginal 신호도 수용. score-based BPH 가 노이즈 제거 담당.
    // Round 129 (실기기 피드백): 케이스백 닫힌 시계(IWC 등) onset 감지율 43% → 임계 0.45→0.35 완화.
    // 낮은 SNR 환경에서 더 많은 beat 감지. false positive는 BPH autocorr 단계에서 필터링.
    static func detectOnsets(
        envelope: [Float],
        sampleRate: Double = 48_000,
        thresholdRatio: Float = 0.25,
        // Round 155 (사용자 보고: 451 beats/30s = 15/s, 28800 의 ~2배 → sub-pulse 가 별도 onset 으로 잡힘).
        // 28800 IOI 125ms → refractory 100ms 로 늘려 sub-pulse(lock/impulse/drop) 차단.
        refractoryMs: Double = 100.0
    ) -> [BeatEvent] {
        guard envelope.count > 0 else { return [] }

        // Round 158: Round 156 이전 working state 복원 — percentile threshold.
        // 사용자 IWC 측정에서 adaptive threshold 가 BPH lock 차단 → revert.
        let originalSorted = envelope.sorted()
        let p95Idx = min(originalSorted.count - 1, (originalSorted.count * 95) / 100)
        let p95 = originalSorted[p95Idx]
        let clipCeiling = max(p95 * 2, 1e-9)
        let clipped: [Float] = envelope.map { min($0, clipCeiling) }

        let sorted = clipped.sorted()
        let bottomHalfCount = max(1, sorted.count / 2)
        let p25BottomIdx = max(0, bottomHalfCount / 4)
        let noiseFloor = sorted[p25BottomIdx]
        let topStart = max(0, sorted.count - max(1, sorted.count / 20))
        let topCount = sorted.count - topStart
        let peak = sorted[topStart + topCount / 2]
        guard peak > noiseFloor * 1.2 else { return [] }
        let threshold = noiseFloor + thresholdRatio * (peak - noiseFloor)

        let refractorySamples = Int(refractoryMs / 1_000 * sampleRate)
        var onsets: [(idx: Int, energy: Float)] = []
        var i = 1
        while i < clipped.count - 1 {
            let v = clipped[i]
            if v >= threshold && v >= clipped[i - 1] && v >= clipped[i + 1] {
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

    /// Round 156 (Aoki + Wang + Petrov 토론): sub-pulse 통합.
    /// IWC 35111 / SW300 등 modern swissLever 는 lock-impulse-drop 3-stage 충격이
    /// 1.8-3.0ms 간격으로 발생 → 5ms flux frame 에서 별도 onset 으로 분리.
    /// 사용자 451 beats/30s = 1.88× 정상 (240) → 약 50% beat 이 2 onset 으로 split.
    ///
    /// 동작: nominalBph 의 IOI 대비 30% 이하 간격(IOI<0.3) 의 인접 onset 쌍을 cluster.
    /// energy-weighted centroid 로 단일 onset 으로 통합. 후속 BPH/rate 분석 안정화.
    ///
    /// nominalBph nil 이면 no-op (regression 안전망).
    static func clusterSubPulses(beats: [BeatEvent], nominalBph: Int?) -> [BeatEvent] {
        guard let bph = nominalBph, bph > 0, beats.count >= 2 else { return beats }
        let expectedIOI = 3600.0 / Double(bph)
        // Round 158 (tickIQ 분석 후): cluster gate 1.2×. user IWC 9.9 Hz onset 패턴 = sub-pulse 검출 →
        // 1.2× gate (9.6 Hz) 가 cluster fire → sub-pulse merge → IOI median 125ms → BPH 28800 lock.
        let duration = beats.last!.timestampSeconds - beats.first!.timestampSeconds
        if duration > 0.5 {
            let observedRate = Double(beats.count - 1) / duration
            let nominalRate = Double(bph) / 3600.0
            if observedRate < nominalRate * 1.2 {
                return beats
            }
        }
        // 30% 이하 간격 = sub-pulse 후보 (28800 의 경우 125ms × 0.3 = 37.5ms)
        let clusterThreshold = expectedIOI * 0.30
        var clustered: [BeatEvent] = []
        clustered.reserveCapacity(beats.count)
        // Round 156 (Min #1 fix): 누적 group span 가드 — 그룹 시작 대비 50% × expectedIOI 초과 금지.
        // 그리디 체이닝(sub-pulse 4+ 연속) 으로 정상 beat 흡수 위험 차단.
        let maxGroupSpan = expectedIOI * 0.50
        var i = 0
        while i < beats.count {
            var groupEnd = i
            let groupStart = beats[i].timestampSeconds
            // 연속된 sub-pulse 들 그룹화 — 그룹 내 last 대비 다음이 threshold 안 + 그룹 시작 대비 maxGroupSpan 안.
            while groupEnd + 1 < beats.count,
                  beats[groupEnd + 1].timestampSeconds - beats[groupEnd].timestampSeconds <= clusterThreshold,
                  beats[groupEnd + 1].timestampSeconds - groupStart <= maxGroupSpan {
                groupEnd += 1
            }
            if groupEnd == i {
                clustered.append(beats[i])
            } else {
                // Energy-weighted centroid — lock impulse (가장 강함) 위치에 가깝게 통합.
                var sumWeight: Double = 0
                var sumWeightedTime: Double = 0
                var maxEnergy: Double = 0
                for j in i...groupEnd {
                    let w = max(beats[j].energy, 1e-9)
                    sumWeight += w
                    sumWeightedTime += beats[j].timestampSeconds * w
                    if beats[j].energy > maxEnergy { maxEnergy = beats[j].energy }
                }
                let centroidTime = sumWeight > 0 ? sumWeightedTime / sumWeight : beats[i].timestampSeconds
                clustered.append(BeatEvent(
                    timestampSeconds: centroidTime,
                    type: beats[i].type,  // parity 는 group 첫 onset 의 type 유지 (refineParity 가 재할당)
                    energy: maxEnergy
                ))
            }
            i = groupEnd + 1
        }
        // tic/toc parity 재할당 — clustering 후 onset 개수 줄었으므로 인덱스 기반으로 재계산.
        var refinedParity: [BeatEvent] = []
        refinedParity.reserveCapacity(clustered.count)
        for (idx, b) in clustered.enumerated() {
            let type: BeatType = idx.isMultiple(of: 2) ? .tic : .toc
            refinedParity.append(BeatEvent(
                timestampSeconds: b.timestampSeconds,
                type: type,
                energy: b.energy
            ))
        }
        return refinedParity
    }

    /// Round 39: Audio-rate parabolic interpolation 으로 onset timestamp sub-sample 정밀도 부여.
    ///
    /// 사용자 보고: live rate +0.0 s/d — 200Hz flux 의 frame quantization (5ms) 한계.
    /// 28800 BPH IOI = 25 frame, 1 frame 변화가 ±1100 s/d 변동 → 작은 drift quantize to 0.
    ///
    /// 동작: 각 onset 의 frame-level timestamp 를 48kHz envelope 위에서 ±searchWindowMs 영역의
    /// 실제 peak 위치로 refine. parabolic interpolation 으로 sub-sample 정밀도.
    /// → timestamp 정밀도 5ms → ~0.02ms (250× 향상) → rate 정밀도 ±5 s/d 이하 가능.
    static func refineTimestamps(
        beats: [BeatEvent],
        envelope: [Float],
        envelopeSampleRate: Double,
        searchWindowMs: Double = 10
    ) -> [BeatEvent] {
        guard !envelope.isEmpty, !beats.isEmpty else { return beats }
        let searchSamples = max(1, Int(searchWindowMs / 1_000 * envelopeSampleRate))
        var refined: [BeatEvent] = []
        refined.reserveCapacity(beats.count)
        for beat in beats {
            let approxIdx = Int(beat.timestampSeconds * envelopeSampleRate)
            let lo = max(1, approxIdx - searchSamples)
            let hi = min(envelope.count - 2, approxIdx + searchSamples)
            guard lo < hi else {
                refined.append(beat)
                continue
            }
            // 1) 영역 안 max 위치
            var maxIdx = lo
            var maxVal: Float = envelope[lo]
            for i in lo...hi where envelope[i] > maxVal {
                maxVal = envelope[i]
                maxIdx = i
            }
            // 2) parabolic interpolation around maxIdx (sub-sample fraction)
            //    y(t) = y_C + (y_R - y_L)/2 · t + (y_L - 2y_C + y_R)/2 · t²
            //    derivative = 0 at t* = -(y_R - y_L) / (2(y_L - 2y_C + y_R)) = 0.5(y_L - y_R)/denom
            let preciseIdx: Double
            if maxIdx > 0 && maxIdx < envelope.count - 1 {
                let yL = envelope[maxIdx - 1]
                let yC = envelope[maxIdx]
                let yR = envelope[maxIdx + 1]
                let denom = yL - 2 * yC + yR
                let delta: Double = denom != 0 ? Double(0.5 * (yL - yR) / denom) : 0
                preciseIdx = Double(maxIdx) + delta.clamped(to: -1...1)  // safety: ±1 sample 까지만
            } else {
                preciseIdx = Double(maxIdx)
            }
            let preciseTimestamp = preciseIdx / envelopeSampleRate
            refined.append(BeatEvent(
                timestampSeconds: preciseTimestamp,
                type: beat.type,
                energy: Double(maxVal)
            ))
        }
        return refined
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
