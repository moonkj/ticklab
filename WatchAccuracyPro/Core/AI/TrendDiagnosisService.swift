import Foundation

/// Sprint 14 (S1, R5 시그니처): 추세 기반 시계공 어조 진단.
/// 단발 verdict(AppleIntelligenceVerdictService)와 달리 측정 히스토리·자세편차·beat error 추이를 종합.
/// 룰 기반 핵심(모든 기기 동작) — 신뢰도 라벨 준수(Hard Rule 9), on-device.
@MainActor
enum TrendDiagnosisService {

    struct Diagnosis {
        let headline: String   // 한 줄 평 (입문자용)
        let coaching: String   // 시계공 어조 상세 (펼침)
        let severity: Severity
    }

    enum Severity { case good, watch, service }

    /// 스트림 D: AI 추세 요약(`AppleIntelligenceVerdictService.trendVerdict`) 입력용 구조화 추세지표.
    /// 룰 진단(`diagnose`)과 동일 계산을 노출해, 자연어 요약 LLM 이 일관된 숫자를 받도록 한다.
    /// amplitude 미포함(Hard Rule 9 무관) — rate/자세편차/beat error 추세만.
    struct TrendMetrics: Equatable {
        /// 최근 측정 구간의 rate 드리프트 (s/d). +면 점점 빨라짐.
        let drift: Double
        /// 최근 rate 평균(절댓값 아님, s/d).
        let avgRate: Double
        /// 자세 간 rate 편차 δ (s/d). 2자세 미만이면 nil.
        let positionalDelta: Double?
        /// 최근 beat error 평균 (ms).
        let avgBeatError: Double
        /// 판정 심각도.
        let severity: Severity
        /// 회귀/추세에 사용된 측정 수.
        let sampleCount: Int
    }

    /// 구조화 추세지표만 산출(자연어 없음). `diagnose` 와 동일 입력 게이트(≥2회).
    static func metrics(watch: Watch, measurements: [WatchMeasurement]) -> TrendMetrics? {
        let sorted = measurements.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2 else { return nil }

        let rates = sorted.map(\.rateSecondsPerDay)
        let recent = Array(rates.suffix(5))
        let drift = (recent.last ?? 0) - (recent.first ?? 0)
        let avgRate = recent.reduce(0, +) / Double(recent.count)
        let absAvg = abs(avgRate)

        var posRates: [Position: [Double]] = [:]
        for m in sorted {
            let p = m.metadata.position
            guard p != .unknown else { continue }
            posRates[p, default: []].append(m.rateSecondsPerDay)
        }
        let posAvgs = posRates.values.compactMap { $0.isEmpty ? nil : $0.reduce(0, +) / Double($0.count) }
        let posDelta: Double? = posAvgs.count >= 2 ? (posAvgs.max()! - posAvgs.min()!) : nil

        let recentBeatError = sorted.suffix(3).map(\.beatErrorMs)
        let avgBeatError = recentBeatError.reduce(0, +) / Double(max(recentBeatError.count, 1))

        let severity: Severity = {
            if let d = posDelta, d >= 15 { return .service }
            if absAvg > 30 || avgBeatError > 1.0 { return .service }
            if abs(drift) > 8 || absAvg > 15 || avgBeatError > 0.5 { return .watch }
            return .good
        }()

        return TrendMetrics(
            drift: drift,
            avgRate: avgRate,
            positionalDelta: posDelta,
            avgBeatError: avgBeatError,
            severity: severity,
            sampleCount: sorted.count
        )
    }

    /// 측정 2회 이상이어야 추세 의미. 미만이면 nil.
    static func diagnose(watch: Watch, measurements: [WatchMeasurement]) -> Diagnosis? {
        let sorted = measurements.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2 else { return nil }

        let rates = sorted.map(\.rateSecondsPerDay)
        let recent = Array(rates.suffix(5))
        let first = recent.first ?? 0
        let last = recent.last ?? 0
        let drift = last - first   // + 면 점점 빨라짐
        let avgRate = recent.reduce(0,+) / Double(recent.count)
        let absAvg = abs(avgRate)

        // 자세별 편차 δ (unknown 제외, 2자세 이상)
        var posRates: [Position: [Double]] = [:]
        for m in sorted {
            let p = m.metadata.position
            guard p != .unknown else { continue }
            posRates[p, default: []].append(m.rateSecondsPerDay)
        }
        let posAvgs = posRates.values.compactMap { $0.isEmpty ? nil : $0.reduce(0,+)/Double($0.count) }
        let posDelta: Double? = posAvgs.count >= 2 ? (posAvgs.max()! - posAvgs.min()!) : nil

        // beat error 추이
        let recentBeatError = sorted.suffix(3).map(\.beatErrorMs)
        let avgBeatError = recentBeatError.reduce(0,+) / Double(max(recentBeatError.count, 1))

        // 심각도 판정
        let severity: Severity = {
            if let d = posDelta, d >= 15 { return .service }
            if absAvg > 30 || avgBeatError > 1.0 { return .service }
            if abs(drift) > 8 || absAvg > 15 || avgBeatError > 0.5 { return .watch }
            return .good
        }()

        // 한 줄 평 (입문자)
        let headline: String = {
            switch severity {
            case .good:    return String(localized: "trend.headline.good")
            case .watch:   return String(localized: "trend.headline.watch")
            case .service: return String(localized: "trend.headline.service")
            }
        }()

        // 시계공 어조 코칭 (델타 기반, amplitude 미언급 → Hard Rule 9 무관)
        var parts: [String] = []
        // rate 추세
        if abs(drift) <= 2 {
            parts.append(String(localized: "trend.coach.stable"))
        } else if drift > 0 {
            parts.append(String(format: NSLocalizedString("trend.coach.gaining", comment: ""), abs(drift)))
        } else {
            parts.append(String(format: NSLocalizedString("trend.coach.losing", comment: ""), abs(drift)))
        }
        // 자세 편차
        if let d = posDelta {
            if d >= 15 {
                parts.append(String(format: NSLocalizedString("trend.coach.positional_high", comment: ""), d))
            } else if d >= 8 {
                parts.append(String(format: NSLocalizedString("trend.coach.positional_mid", comment: ""), d))
            } else {
                parts.append(String(format: NSLocalizedString("trend.coach.positional_low", comment: ""), d))
            }
        }
        // beat error
        if avgBeatError > 0.5 {
            parts.append(String(format: NSLocalizedString("trend.coach.beat_error", comment: ""), avgBeatError))
        }
        // 권고
        switch severity {
        case .service: parts.append(String(localized: "trend.coach.advise_service"))
        case .watch:   parts.append(String(localized: "trend.coach.advise_watch"))
        case .good:    parts.append(String(localized: "trend.coach.advise_good"))
        }

        return Diagnosis(headline: headline, coaching: parts.joined(separator: " "), severity: severity)
    }
}
