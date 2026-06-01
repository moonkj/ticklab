import Foundation

// MARK: - FastRateConvergence
// "빠른 측정" 프로토타입의 핵심(순수) 로직.
// 검증된 엔진(DSPPipeline의 autocorrelation analyze)을 그대로 쓰되, 윈도우를 키워가며
// rate 추정이 안정되는 최소 시점을 찾아 조기 종료한다. 새 rate 수학 없음 → 편향 위험 없음.
//
// 검토 판정(docs/dsp/proposed_fast_rate/REVIEW_VERDICT.md)의 viable 경로:
//   속도 = 조기 종료(수렴 시), 정확도 = 기존 rawBph/autocorrelation 그대로.

enum FastRateConvergence {

    /// 증가하는 윈도우(초)별 rate 추정 시퀀스에서, 최근 `stableCount`개가 서로
    /// `toleranceSecondsPerDay` 이내면 수렴으로 판정하고 그 시점을 반환.
    /// - Parameters:
    ///   - rates: (윈도우 초, rate s/d) — 윈도우 오름차순 가정.
    ///   - toleranceSecondsPerDay: 연속 추정 간 최대 허용 스프레드(max-min).
    ///   - stableCount: 안정으로 볼 연속 추정 개수.
    /// - Returns: 수렴 시점 (seconds, index). 미수렴 시 nil.
    static func firstStableWindow(
        rates: [(seconds: Double, rate: Double)],
        toleranceSecondsPerDay: Double = 2.0,
        stableCount: Int = 3
    ) -> (seconds: Double, index: Int)? {
        guard stableCount >= 1, rates.count >= stableCount else { return nil }
        for i in (stableCount - 1)..<rates.count {
            let window = rates[(i - stableCount + 1)...i].map(\.rate)
            guard let lo = window.min(), let hi = window.max() else { continue }
            if hi - lo <= toleranceSecondsPerDay {
                return (rates[i].seconds, i)
            }
        }
        return nil
    }
}

// MARK: - DSPPipeline early-exit (부가 — 기존 analyze/stop 동작 불변)

extension DSPPipeline {

    struct EarlyExitOutcome {
        let result: MeasurementResult
        let convergedSeconds: Double
        let windowsTried: Int
        let didConverge: Bool
    }

    /// 누적 버퍼 위에서 증가하는 윈도우로 analyze 하며 rate 수렴 시점을 찾는다.
    /// 수렴하면 그 윈도우 결과 + 시점, 미수렴이면 최종(최대) 윈도우 결과를 반환.
    /// ⚠️ 기존 측정 경로(stop/analyze)는 변경하지 않는 **부가 메서드**. 플래그 게이트로만 사용.
    func measureEarlyExit(
        candidateWindows: [Double],
        toleranceSecondsPerDay: Double = 2.0,
        stableCount: Int = 3
    ) -> EarlyExitOutcome? {
        var rates: [(seconds: Double, rate: Double)] = []
        var resultsByWindow: [Double: MeasurementResult] = [:]

        for w in candidateWindows.sorted() {
            guard let r = analyze(windowSeconds: w) else { continue }
            resultsByWindow[w] = r
            rates.append((w, r.rateSecondsPerDay))

            if let conv = FastRateConvergence.firstStableWindow(
                rates: rates,
                toleranceSecondsPerDay: toleranceSecondsPerDay,
                stableCount: stableCount
            ) {
                let res = resultsByWindow[conv.seconds] ?? r
                return EarlyExitOutcome(result: res, convergedSeconds: conv.seconds,
                                        windowsTried: rates.count, didConverge: true)
            }
        }

        if let last = rates.last, let res = resultsByWindow[last.seconds] {
            return EarlyExitOutcome(result: res, convergedSeconds: last.seconds,
                                    windowsTried: rates.count, didConverge: false)
        }
        return nil
    }
}
