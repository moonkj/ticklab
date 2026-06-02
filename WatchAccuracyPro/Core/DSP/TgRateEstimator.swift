import Accelerate
import Foundation

/// Round 172 (사용자 제안 + `tg` 오픈소스 분석): envelope **자기상관 + multi-cycle 정밀화** 기반 rate.
///
/// 배경: 기존 onset-OLS / 200Hz autocorrelation 은 개별 onset 검출/거친 lag 때문에 고정 시계에서도
/// 측정마다 주기가 ±15 s/d 흔들렸다(win[] ±25). `tg` 타임그래퍼의 기법을 clean-room 재구현:
///   - 개별 onset 을 **검출하지 않는다** → onset jitter 원천 제거.
///   - 48kHz envelope 전체의 자기상관을 쓴다(전 구간 평균 → 강건).
///   - **multi-cycle long-baseline**: 주기 P 는 lag P,2P,…,K·P 마다 peak. 큰 K 의 peak 위치 ÷ K 로
///     구하면 정밀도가 K배. 30초·48kHz 면 K~150 → ~0.03 s/d 이론 정밀도.
///
/// ⚠️ `tg`(GPL) 코드 복사 아님 — autocorrelation+harmonic refine 은 표준 DSP. Swift clean-room 구현.
enum TgRateEstimator {

    struct Result: Equatable {
        let beatPeriodSamples: Double   // 정밀화된 beat(tic→toc) 주기 (샘플)
        let rate: Double                // 초/일
        let sigma: Double               // cycle 간 추정 일관성(s/d) — 작을수록 신뢰.
        let cyclesUsed: Int             // 최종 정밀화에 쓴 cycle 수 K (baseline 길이).
    }

    /// - Parameters:
    ///   - envelope: 48kHz rectified/smoothed envelope (analyzeSimplified 의 envSlice).
    ///   - sampleRate: envelope 샘플레이트 (보통 48000).
    ///   - nominalBph: 명목 BPH (lag 탐색 중심).
    ///   - clockDriftFactor: 오디오↔호스트 클록 드리프트 보정(host/audio). true period = lag/sr × factor.
    ///     1.0 = 무보정(합성/테스트). AudioCapture 가 AVAudioTime 으로 산출(예: −80ppm → 0.99992).
    static func estimate(envelope: [Float], sampleRate: Double, nominalBph: Int, clockDriftFactor: Double = 1.0) -> Result? {
        let n = envelope.count
        guard nominalBph > 0, sampleRate > 0 else { return nil }
        let nominalBeatSec = 3600.0 / Double(nominalBph)        // 0.125s @28800
        let nominalBeatLag = nominalBeatSec * sampleRate         // 6000 @48k
        guard nominalBeatLag >= 8, n > Int(nominalBeatLag * 6) else { return nil }  // 최소 ~6 beats

        // 평균 제거(자기상관 DC 편향 방지). envelope 는 음이 아니므로 mean 빼면 진동.
        var env = [Float](repeating: 0, count: n)
        var mean: Float = 0
        envelope.withUnsafeBufferPointer { vDSP_meanv($0.baseAddress!, 1, &mean, vDSP_Length(n)) }
        var negMean = -mean
        envelope.withUnsafeBufferPointer { src in
            env.withUnsafeMutableBufferPointer { dst in
                vDSP_vsadd(src.baseAddress!, 1, &negMean, dst.baseAddress!, 1, vDSP_Length(n))
            }
        }

        // 특정 lag 의 비정규화 자기상관 (겹치는 구간 dot product).
        func autocorr(_ lag: Int) -> Double {
            guard lag > 0, lag < n else { return 0 }
            var dp: Float = 0
            env.withUnsafeBufferPointer { p in
                vDSP_dotpr(p.baseAddress!, 1, p.baseAddress! + lag, 1, &dp, vDSP_Length(n - lag))
            }
            // 겹침 길이로 정규화(긴 lag 에서 값이 작아지는 것 보정 → peak 비교 공정).
            return Double(dp) / Double(n - lag)
        }

        // center 근방 ±halfWin 정수 lag 에서 최대 찾고 포물선 보간으로 sub-sample peak.
        func refinePeak(center: Double, halfWin: Int) -> Double? {
            let c = Int(center.rounded())
            let lo = max(1, c - halfWin), hi = min(n - 2, c + halfWin)
            guard lo < hi else { return nil }
            var bestLag = lo
            var bestVal = autocorr(lo)
            var l = lo + 1
            while l <= hi {
                let v = autocorr(l)
                if v > bestVal { bestVal = v; bestLag = l }
                l += 1
            }
            let yL = autocorr(bestLag - 1), yC = autocorr(bestLag), yR = autocorr(bestLag + 1)
            let denom = yL - 2 * yC + yR
            let delta = denom != 0 ? 0.5 * (yL - yR) / denom : 0
            return Double(bestLag) + Swift.max(-1.0, Swift.min(1.0, delta))
        }

        // 1) 거친 beat 주기 — 명목 ±15% 범위에서 peak.
        guard var beatLag = refinePeak(center: nominalBeatLag, halfWin: Int(nominalBeatLag * 0.15)) else { return nil }
        // 명목에서 너무 벗어나면(±20% 초과) 잘못된 lock — 거부.
        guard abs(beatLag - nominalBeatLag) / nominalBeatLag <= 0.20 else { return nil }

        // 2) multi-cycle 정밀화 — K 를 배수로 키우며 K·beatLag 근방 peak / K 로 갱신.
        //    각 단계 추정이 정밀해 다음 K 의 좁은 창에 peak 가 들어온다.
        var perCycle: [Double] = [beatLag]
        let maxK = Int(0.7 * Double(n) / beatLag)
        var k = 2
        var lastK = 1
        while k <= maxK {
            // 창은 직전 추정 오차 × k 를 덮도록 beatLag 의 ±8%.
            guard let pk = refinePeak(center: beatLag * Double(k), halfWin: Int(beatLag * 0.08)) else { break }
            let est = pk / Double(k)
            // 갱신값이 비합리적이면(±2%↑ 점프) 그 단계 무시하고 종료.
            guard abs(est - beatLag) / beatLag <= 0.02 else { break }
            beatLag = est
            perCycle.append(est)
            lastK = k
            k *= 2
        }

        // Round 172: 클록 드리프트 보정 — true period = 측정 period × (host/audio).
        let beatSec = beatLag / sampleRate * clockDriftFactor
        guard beatSec > 0 else { return nil }
        let rate = (nominalBeatSec - beatSec) / beatSec * 86400.0
        guard abs(rate) <= 300 else { return nil }

        // sigma: cycle 별 추정의 s/d 환산 표준편차(일관성). 보정은 상수배라 sigma 에 영향 미미.
        let perRates = perCycle.map { lag -> Double in
            let s = lag / sampleRate * clockDriftFactor
            return (nominalBeatSec - s) / s * 86400.0
        }
        let m = perRates.reduce(0, +) / Double(perRates.count)
        let variance = perRates.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(Swift.max(1, perRates.count))
        let sigma = variance.squareRoot()

        return Result(beatPeriodSamples: beatLag, rate: rate, sigma: sigma, cyclesUsed: lastK)
    }
}
