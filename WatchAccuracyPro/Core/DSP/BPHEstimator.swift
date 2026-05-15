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
/// 알고리즘 (사용자 보고된 ±129600 s/d 광기 수정):
/// - 표준 BPH 6개 (18000/21600/25200/28800/36000 + 19800)에 해당하는 lag 만 평가.
/// - 각 표준 lag 주변 ±1.5% 윈도우에서 max R 찾고, parabolic interpolation 으로 sub-sample 정밀도 확보.
/// - 후보 중 R 가 가장 큰 표준 BPH 채택.
/// - 최종 confidence (R/R0) 가 minConfidence 미만이면 nil 반환 — 신뢰 못 할 측정에 가짜 숫자 안 만들도록.
///
/// 이전 알고리즘은 "가장 짧은 유의미 peak" 를 inter-onset 으로 간주했는데, 실 환경 노이즈에서
/// 50ms 부근 spurious peak 에 끌려 72000 BPH 같은 광기의 값이 나옴. anchor-to-standard 로 차단.
enum BPHEstimator {
    /// Round 89 (김재철 Critical) + Round 102 (최용수 Critical): vintage BPH 추가.
    /// 8400 = 1900s pocket watch, 12000 = vintage Omega 30T2, 14400 = vintage Hamilton,
    /// 16200 = vintage Omega 30mm, 21000 = vintage AS calibre.
    /// 표준 6개 → 11개로 확장. 낮은 BPH 는 lag 가 길어 autocorrelation R/R0 낮아도 lock 시도 의미 있음.
    /// Round 122 (DSP High): Breguet Cal.502.3 35800 BPH 추가 — 없으면 36000 으로 snap해 ±4.8 s/d 오차.
    static let standardBPHs: [Int] = [8_400, 12_000, 14_400, 16_200, 18_000, 19_800, 21_000, 21_600, 25_200, 28_800, 35_800, 36_000]

    /// 이 값보다 R(τ*)/R(0) 이 낮으면 autocorrelation 신뢰 X.
    /// Round 30: 0.05→0.03. Round 129b: IWC SNR 16dB ONSETS 156인데도 lock 실패 → 0.008→0.003.
    /// 케이스 댐핑 강한 시계 R/R0 매우 낮음. nominalBphHint 있으면 false lock 거의 불가능 (±20% 범위 제한).
    static let minConfidence: Double = 0.003

    /// 진입점 — autocorrelation 우선 (flux signal 위에서 매우 robust).
    /// 사용자 보고: onset count 가 secondary peak 로 14% 초과 (110 vs 96 expected) → score-based 가 36000 잘못 픽.
    /// **autocorrelation 위주**: 표준 BPH lag 마다 R/R0 계산. 노이즈 onset 영향 받지 않음.
    /// onset-based 는 autocorrelation 결과 검증 보조.
    /// Round 34: `nominalBphHint` 추가 — 사용자가 무브먼트 선택했으면 그 nominal BPH 의 ±20% 안만 lock 후보.
    /// 36000 같은 잘못된 lock 차단 + 28800 정상 lock 회복.
    static func estimate(
        envelope: [Float],
        beats: [BeatEvent] = [],
        sampleRate: Double = 48_000,
        nominalBphHint: Int? = nil
    ) -> BPHEstimate? {
        let autoEst = estimateAutocorrelation(envelope: envelope, sampleRate: sampleRate, nominalBphHint: nominalBphHint)
        let onsetEst = beats.count >= 8 ? estimateFromOnsets(beats: beats, envelope: envelope, nominalBphHint: nominalBphHint) : nil

        // Round 32: 둘 다 있고 BPH 다를 때 — **onsetEst 우선** (이전: confidence 비교).
        // 사용자 보고 91/70/117/47 onsets 어떤 케이스도 lock 못함. 200Hz flux 위 autocorr 가 wrong
        // lag 잡은 가능성 큼 (lag granularity 거침). onsetEst (특히 IOI median fallback) 는 직접 IOI 분포
        // 보므로 사용자 실 device 케이스에서 더 robust. autoEst 는 confirm 역할만.
        switch (autoEst, onsetEst) {
        case (let a?, let o?):
            if a.bph == o.bph {
                return BPHEstimate(
                    bph: a.bph,
                    rawBph: a.rawBph,
                    confidence: Swift.min(1.0, a.confidence + o.confidence * 0.5),
                    peakLagSeconds: a.peakLagSeconds
                )
            }
            return o  // onsetEst 우선
        case (let a?, nil):  return a
        case (nil, let o?):  return o
        case (nil, nil):
            // Round 129c (사용자: 사람 귀에 들리는데 lock 실패): 최후 fallback — onset rate 단순 추정.
            // 임계값 다 통과 못한 marginal 신호도 결과는 반환. 신뢰도는 매우 낮음 (0.01).
            return fallbackFromOnsetRate(beats: beats, nominalBphHint: nominalBphHint)
        }
    }

    /// Round 131: fallback drift 50%/60% → 15%로 다시 엄격하게. garbage lock 방지가 우선.
    /// rate +216.5 s/d 같은 비정상값은 BPH 잘못 lock → rate 잘못 계산의 결과.
    /// fallback 통과 못해 nil 반환 시 → lockFailure UI → 사용자에게 "재측정" 안내 (정확함).
    private static func fallbackFromOnsetRate(beats: [BeatEvent], nominalBphHint: Int?) -> BPHEstimate? {
        guard beats.count >= 20 else { return nil }
        let timeSpan = beats.last!.timestampSeconds - beats.first!.timestampSeconds
        guard timeSpan >= 5 else { return nil }
        let onsetRate = Double(beats.count) / timeSpan
        let rawBph = onsetRate * 1800
        let candidates = nominalBphHint.map { hint in
            hint > 0 ? standardBPHs.filter { abs(Double($0 - hint)) / Double(hint) <= 0.20 } : standardBPHs
        } ?? standardBPHs
        let snapped = nearestStandardBPH(rawBph, candidates: candidates)
        let drift = abs(Double(snapped) - rawBph) / Double(snapped)
        // Round 131 (사용자 garbage rate +216 보고): drift 50% → 15% 엄격.
        // 잘못된 lock 으로 부정확 rate 출력하는 것보다 lockFailure 가 사용자에게 더 정직.
        guard drift < 0.15 else { return nil }
        return BPHEstimate(
            bph: snapped,
            rawBph: rawBph,
            confidence: 0.05,
            peakLagSeconds: 1.0 / onsetRate
        )
    }

    /// **Score-based BPH 검출** — robust to noisy onset detection.
    /// 각 표준 BPH 의 expected interval 에 대해, 실제 intervals 중 ±10% 이내인 개수를 셈.
    /// 가장 매칭 많은 BPH 가 winner.
    /// 사용자 보고: median 방식이 secondary-peak 노이즈에 약했음. score 방식은 노이즈 자연 제거.
    static func estimateFromOnsets(beats: [BeatEvent], envelope: [Float], nominalBphHint: Int? = nil) -> BPHEstimate? {
        guard beats.count >= 8 else { return nil }
        var intervals: [Double] = []
        intervals.reserveCapacity(beats.count - 1)
        for i in 1..<beats.count {
            intervals.append(beats[i].timestampSeconds - beats[i - 1].timestampSeconds)
        }
        // Round 129d (사용자 측정 안됨): valid filter 대폭 완화 — 0.060→0.040, 0.500→0.800.
        // 36000 BPH (10ms IOI?) ~ 8400 BPH (430ms IOI) 모두 포함. jitter 큰 환경 흡수.
        let valid = intervals.filter { $0 >= 0.040 && $0 <= 0.800 }
        guard valid.count >= 6 else { return nil }

        // 각 표준 BPH 점수 계산.
        // Round 30 fix: tie (예: 21600 vs 19800 둘 다 17/17 matches) 시 IOI mean drift 작은 candidate 채택.
        // 이전엔 standardBPHs 순서상 먼저인 19800 잘못 채택해 21600 lock 회귀 유발.
        // Round 34: nominalBphHint 있으면 ±20% 안의 표준 BPH 만 후보 — 잘못된 lock (예: 28800 시계의 36000 lock) 차단.
        let candidates: [Int] = nominalBphHint.map { hint in
            // Round 104 (Swift High): hint=0 이면 division by zero → NaN → 모든 후보 차단.
            // quartz(bph=0) 는 Round 98 에서 이미 start() 에서 차단되므로 방어 가드.
            hint > 0 ? standardBPHs.filter { abs(Double($0 - hint)) / Double(hint) <= 0.20 } : standardBPHs
        } ?? standardBPHs
        struct CandidateScore { let bph: Int; let matches: [Double]; let count: Int; let driftFromExpected: Double }
        var bestCandidate: CandidateScore?
        for bph in candidates {
            let expected = 3600.0 / Double(bph)
            let tolerance = expected * 0.10  // ±10%
            let matches = valid.filter { abs($0 - expected) <= tolerance }
            guard !matches.isEmpty else { continue }
            let matchMean = matches.reduce(0, +) / Double(matches.count)
            let drift = abs(matchMean - expected) / expected
            let candidate = CandidateScore(bph: bph, matches: matches, count: matches.count, driftFromExpected: drift)
            if let cur = bestCandidate {
                if matches.count > cur.count
                   || (matches.count == cur.count && drift < cur.driftFromExpected) {
                    bestCandidate = candidate
                }
            } else {
                bestCandidate = candidate
            }
        }

        // Round 37: matchRatio 0.30 → 0.20 (원래 값 복귀). tickIQ "정확치는 않지만 측정 되긴 함"
        // 동작 흉내 — marginal 신호도 통과. nominal-guided + drift guard 가 광기 lock 차단.
        if let best = bestCandidate, best.count >= 4 {
            let matchRatio = Double(best.count) / Double(valid.count)
            if matchRatio >= 0.20 {
                let sortedMatches = best.matches.sorted()
                let preciseInterval = sortedMatches[sortedMatches.count / 2]
                let rawBph = 3600.0 / preciseInterval
                let mean = best.matches.reduce(0, +) / Double(best.count)
                let variance = best.matches.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(best.count)
                let cv = sqrt(variance) / mean
                let consistencyConf = Swift.max(0, Swift.min(1, 1 - cv * 5))
                return BPHEstimate(
                    bph: best.bph,
                    rawBph: rawBph,
                    confidence: matchRatio * consistencyConf,
                    peakLagSeconds: preciseInterval
                )
            }
        }

        // Round 30 — IOI-median fallback.
        // 사용자 보고: 91 onsets / 12s 인데도 BPH lock 실패. 가설: autocorrelation 의 lag granularity
        // 거침 + tolerance window jitter 흡수 부족. onset 풍부할 때만 (>= 30) 진입 — 적은 onset 의 합성
        // 테스트가 fallback 에 진입해 잘못 lock 하는 회귀 차단.
        // Round 34: candidates (nominalBphHint 적용) 안에서 nearest BPH 찾기 — 사용자 신호 잡힌 BPH 가
        // 잘못된 standard (예: 36000) 로 snap 되는 case 차단.
        // Round 129c (사용자: "사람 귀에 들리는데"): 매우 완화. 사람 청각 검증된 신호는 무조건 lock 시도.
        guard valid.count >= 15 else { return nil }
        let sortedAll = valid.sorted()
        let medianIOI = sortedAll[sortedAll.count / 2]
        let rawBph = 3600.0 / medianIOI
        let snapped = nearestStandardBPH(rawBph, candidates: candidates)
        let drift = abs(Double(snapped) - rawBph) / Double(snapped)
        // 10% → 18% 완화 (jitter 큰 환경).
        guard drift < 0.18 else { return nil }
        let expectedAtSnapped = 3600.0 / Double(snapped)
        // tolerance 10% → 15% 완화.
        let tolerance = expectedAtSnapped * 0.15
        let near = valid.filter { abs($0 - expectedAtSnapped) <= tolerance }.count
        let conf = Double(near) / Double(valid.count)
        // 0.25 → 0.12 완화 (사람 귀에 들리는 신호 무조건 lock).
        guard conf >= 0.12 else { return nil }
        return BPHEstimate(
            bph: snapped,
            rawBph: rawBph,
            confidence: conf,
            peakLagSeconds: medianIOI
        )
    }

    static func estimateAutocorrelation(envelope: [Float], sampleRate: Double = 48_000, nominalBphHint: Int? = nil) -> BPHEstimate? {
        guard envelope.count > Int(sampleRate * 0.5) else { return nil }
        // Round 34: nominalBphHint 있으면 ±20% 안의 표준 BPH 만 후보.
        let candidates: [Int] = nominalBphHint.map { hint in
            // Round 104 (Swift High): hint=0 이면 division by zero → NaN → 모든 후보 차단.
            // quartz(bph=0) 는 Round 98 에서 이미 start() 에서 차단되므로 방어 가드.
            hint > 0 ? standardBPHs.filter { abs(Double($0 - hint)) / Double(hint) <= 0.20 } : standardBPHs
        } ?? standardBPHs

        // DC + slow drift 제거 — 단순 mean 빼는 대신 moving average 빼서 baseline drift 까지 제거.
        // 마이크 핸들링이나 환경 변화로 envelope 가 천천히 변하면 short-lag R 가 그 drift 에 압도됨.
        // window = 50ms (= 0.05 × sampleRate) 로 watch period 보다 짧게.
        let detrendWindow = max(1, Int(sampleRate * 0.05))
        var centered = [Float](repeating: 0, count: envelope.count)
        Self.subtractMovingAverage(envelope, into: &centered, window: detrendWindow)

        var r0: Float = 0
        vDSP_dotpr(centered, 1, centered, 1, &r0, vDSP_Length(centered.count))
        guard r0 > 0 else { return nil }

        // 각 표준 BPH 의 inter-beat lag 에서 R 측정.
        var lagCandidates: [(bph: Int, lag: Int, r: Float, lagD: Double, rD: Float)] = []
        for bph in candidates {
            let periodSeconds = 3600.0 / Double(bph)
            let centerLag = Int((periodSeconds * sampleRate).rounded())
            // Round 130 (Chen P5): nominalBphHint 있으면 ±5% (lag granularity 보완), 없으면 ±1.5% (안전).
            // hint 있으면 candidates 이미 ±20%로 제한돼서 인접 표준 lock 위험 없음.
            let halfPct: Double = nominalBphHint != nil ? 0.05 : 0.015
            let halfWindow = max(2, Int(Double(centerLag) * halfPct))
            let lo = max(1, centerLag - halfWindow)
            let hi = min(envelope.count - 1, centerLag + halfWindow)
            guard lo <= hi else { continue }

            var localMaxR: Float = -.infinity
            var localMaxLag = lo
            centered.withUnsafeBufferPointer { ptr in
                let base = ptr.baseAddress!
                for lag in lo...hi {
                    let count = envelope.count - lag
                    guard count > 0 else { return }
                    var r: Float = 0
                    vDSP_dotpr(base, 1, base.advanced(by: lag), 1, &r, vDSP_Length(count))
                    if r > localMaxR {
                        localMaxR = r
                        localMaxLag = lag
                    }
                }
            }

            // parabolic interpolation around localMaxLag (조금 더 정밀한 BPH 추정)
            let lagD: Double
            if localMaxLag > lo && localMaxLag < hi {
                var rL: Float = 0, rR: Float = 0
                centered.withUnsafeBufferPointer { ptr in
                    let base = ptr.baseAddress!
                    let cL = envelope.count - (localMaxLag - 1)
                    let cR = envelope.count - (localMaxLag + 1)
                    if cL > 0 {
                        vDSP_dotpr(base, 1, base.advanced(by: localMaxLag - 1), 1, &rL, vDSP_Length(cL))
                    }
                    if cR > 0 {
                        vDSP_dotpr(base, 1, base.advanced(by: localMaxLag + 1), 1, &rR, vDSP_Length(cR))
                    }
                }
                let denom = rL - 2 * localMaxR + rR
                let delta = denom != 0 ? 0.5 * (rL - rR) / denom : 0
                lagD = Double(localMaxLag) + Double(delta)
            } else {
                lagD = Double(localMaxLag)
            }

            lagCandidates.append((bph: bph, lag: localMaxLag, r: localMaxR, lagD: lagD, rD: localMaxR))
        }

        // R 이 가장 큰 표준 BPH 후보 찾기.
        guard let max = lagCandidates.max(by: { $0.r < $1.r }), max.r > 0 else {
            return nil
        }
        // Round 30: 'smaller BPH preferred' 는 정수배 lag (harmonic) 관계일 때만 fundamental 선호.
        // 21600 (lag 33) 와 19800 (lag 36) 처럼 인접 표준은 정수배 아님 → 단순히 max.r 채택.
        // 이전 'strong.max(by: smaller BPH)' 는 21600 신호의 19800 weak peak 잘못 채택해 회귀 유발.
        let strongThreshold = max.r * 0.85
        let strong = lagCandidates.filter { $0.r >= strongThreshold }
        let chosen: (bph: Int, lag: Int, r: Float, lagD: Double, rD: Float)
        if strong.count > 1 {
            let sortedByLag = strong.sorted(by: { $0.lag < $1.lag })
            let shortest = sortedByLag[0]
            let isHarmonicFamily = sortedByLag.dropFirst().allSatisfy { c in
                let ratio = Double(c.lag) / Double(shortest.lag)
                return abs(ratio - ratio.rounded()) < 0.05 && ratio >= 1.8
            }
            chosen = isHarmonicFamily ? shortest : max  // fundamental vs 인접 모호성
        } else {
            chosen = max
        }

        var confidence = Double(chosen.r / r0)
        var bestLagD = chosen.lagD
        var bestStandardBPH = chosen.bph

        // 표준 BPH 매칭이 약하면 — 60-500ms 전체 범위 sweep 으로 peak 찾기 시도.
        // 사용자 보고: 일부 시계는 표준 BPH ±1.5% 윈도우 밖에 lock 될 수 있음 (drift 큰 경우).
        if confidence < minConfidence * 2 {
            if let sweepBest = sweepBestLag(centered: centered, sampleRate: sampleRate) {
                let sweepConf = Double(sweepBest.r / r0)
                if sweepConf > confidence {
                    confidence = sweepConf
                    bestLagD = sweepBest.lagD
                    bestStandardBPH = nearestStandardBPH(3600.0 / (sweepBest.lagD / sampleRate), candidates: candidates)
                }
            }
        }

        // 신호 너무 약하면 nil — 광기의 숫자 만들지 않도록.
        guard confidence >= minConfidence else { return nil }

        let periodSeconds = bestLagD / sampleRate
        let rawBph = 3_600.0 / periodSeconds
        // Round 37 (tickIQ 측정 됨, 우리 strict guard 가 정상 측정 차단): 12% → 18% 추가 완화 (사용자 보고 측정 안됨).
        // 광기 lock (drift 50%+) 는 차단 유지, marginal lock 은 통과 허용.
        let driftFromStandard = abs(rawBph - Double(bestStandardBPH)) / Double(bestStandardBPH)
        guard driftFromStandard < 0.18 else { return nil }
        return BPHEstimate(
            bph: bestStandardBPH,
            rawBph: rawBph,
            confidence: confidence,
            peakLagSeconds: periodSeconds
        )
    }

    /// 60ms–1000ms 범위에서 가장 강한 peak 검색 (sweep). 표준 BPH 매칭이 실패할 때 fallback.
    /// Round 122 (DSP Critical): 8400 BPH lag = 857ms — 500ms 상한에서 못 잡히던 버그 수정.
    private static func sweepBestLag(centered: [Float], sampleRate: Double) -> (lagD: Double, r: Float)? {
        let minLag = max(1, Int(sampleRate * 0.060))   // 60ms = 60000 BPH
        let maxLag = min(centered.count - 1, Int(sampleRate * 1.000))  // 1000ms → 3600 BPH cover
        guard minLag < maxLag else { return nil }
        var bestR: Float = -.infinity
        var bestLag = minLag
        var rValues = [Float]()
        rValues.reserveCapacity(maxLag - minLag + 1)
        centered.withUnsafeBufferPointer { ptr in
            let base = ptr.baseAddress!
            for lag in minLag...maxLag {
                let count = centered.count - lag
                guard count > 0 else { break }
                var r: Float = 0
                vDSP_dotpr(base, 1, base.advanced(by: lag), 1, &r, vDSP_Length(count))
                rValues.append(r)
                if r > bestR { bestR = r; bestLag = lag }
            }
        }
        // parabolic interpolation around best
        let idx = bestLag - minLag
        let lagD: Double
        if idx > 0, idx < rValues.count - 1 {
            let yL = rValues[idx - 1], yC = rValues[idx], yR = rValues[idx + 1]
            let denom = yL - 2 * yC + yR
            let delta = denom != 0 ? 0.5 * (yL - yR) / denom : 0
            lagD = Double(bestLag) + Double(delta)
        } else {
            lagD = Double(bestLag)
        }
        return (lagD: lagD, r: bestR)
    }

    /// 입력 신호에서 moving-average 를 빼 baseline drift 를 제거.
    /// prefix sum 기반 O(n) — edge effect 자동 처리.
    static func subtractMovingAverage(_ input: [Float], into output: inout [Float], window: Int) {
        let n = input.count
        guard n > 0, output.count >= n else { return }
        let half = max(1, window / 2)
        var prefix = [Float](repeating: 0, count: n + 1)
        for i in 0..<n { prefix[i + 1] = prefix[i] + input[i] }
        for i in 0..<n {
            let lo = max(0, i - half)
            let hi = min(n - 1, i + half)
            let sum = prefix[hi + 1] - prefix[lo]
            let count = Float(hi - lo + 1)
            let avg = count > 0 ? sum / count : 0
            output[i] = input[i] - avg
        }
    }

    static func nearestStandardBPH(_ raw: Double, candidates: [Int]? = nil) -> Int {
        let pool = candidates ?? standardBPHs
        var bestDiff = Double.infinity
        var bestBph = pool.first ?? standardBPHs[0]
        for bph in pool {
            let d = abs(raw - Double(bph))
            if d < bestDiff {
                bestDiff = d
                bestBph = bph
            }
        }
        return bestBph
    }
}
