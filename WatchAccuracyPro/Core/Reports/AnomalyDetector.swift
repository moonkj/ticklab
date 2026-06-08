import Foundation

/// 스트림 D: 단일 시계 시계열 이상탐지.
///
/// 신규(최신) 측정이 **과거 분포(median + MAD)** 대비 통계적 급변인지 판정한다.
/// RateAggregate 의 MAD outlier 패턴과 동일 척도(σ ≈ MAD × 1.4826)를 사용해, 동떨어진 측정을
/// rate 또는 beatError 축에서 감지하고 사유(자성화·충격 의심 등)를 반환한다.
///
/// 핵심은 `[Double]` 입력 순수 함수(`detect(history:latest:...)`)로 분리 → 단위 테스트 가능.
/// 표시는 StatsView 카드 한정(다른 측정 화면 금지). on-device·외부 전송 0.
enum AnomalyDetector {

    /// 이상 사유. 표시 문자열은 StatsView 가 `anomaly.reason.*` 키로 매핑.
    enum Reason: String, Equatable {
        /// rate 가 갑자기 크게 빨라짐 — 자성화 의심(자성화는 보통 rate 를 +로 끌어올림).
        case suspectMagnetization
        /// rate 가 갑자기 크게 느려짐 — 충격/오일 마름 의심.
        case suspectShock
        /// beat error 급증 — 탈진기/밸런스 충격 의심.
        case suspectBeatErrorSpike
    }

    /// 탐지 결과.
    struct Anomaly: Equatable {
        let reason: Reason
        /// 과거 중앙값 대비 신규 측정의 편차(σ 단위, 부호 보존). 진단 강도.
        let deviationSigma: Double
        /// 신규 측정 rate (s/d) — 카드 표시용.
        let latestRate: Double
        /// 과거 중앙값 rate (s/d) — 카드 표시용.
        let baselineRate: Double
    }

    /// 과거 분포 대비 신규 측정을 평가하기 위한 최소 과거 표본 수.
    static let minHistoryCount = 4
    /// 이상 판정 임계 — |편차| > K·σ. RateAggregate outlierK(3.0) 보다 약간 보수적.
    static let defaultSigmaThreshold = 3.5
    /// MAD 가 0/작아도 정상 변동으로 보는 절대 floor (s/d). RateAggregate(5.0)와 정합.
    static let rateAbsoluteFloor = 8.0
    /// beat error 급증 절대 floor (ms) — 미세 변동을 이상으로 오판하지 않도록.
    static let beatErrorAbsoluteFloor = 0.6

    /// WatchMeasurement 시계열에서 가장 최근 측정의 이상 여부 판정.
    /// - Parameter measurements: 한 시계의 전체 측정(정렬 무관). 내부에서 timestamp 정렬 후 최신 1건을 신규로 본다.
    static func detectLatest(
        measurements: [WatchMeasurement],
        sigmaThreshold: Double = defaultSigmaThreshold
    ) -> Anomaly? {
        guard measurements.count > minHistoryCount else { return nil }
        let sorted = measurements.sorted { $0.timestamp < $1.timestamp }
        guard let latest = sorted.last else { return nil }
        let history = Array(sorted.dropLast())
        return detect(
            historyRates: history.map(\.rateSecondsPerDay),
            historyBeatErrors: history.map(\.beatErrorMs),
            latestRate: latest.rateSecondsPerDay,
            latestBeatError: latest.beatErrorMs,
            sigmaThreshold: sigmaThreshold
        )
    }

    /// 순수 함수 핵심 — 과거 rate/beatError 분포 vs 신규 측정. 테스트 가능.
    /// rate 와 beatError 각각 median+MAD 로 평가 → 더 큰 |편차σ| 축을 사유로 채택.
    static func detect(
        historyRates: [Double],
        historyBeatErrors: [Double],
        latestRate: Double,
        latestBeatError: Double,
        sigmaThreshold: Double = defaultSigmaThreshold
    ) -> Anomaly? {
        guard historyRates.count >= minHistoryCount else { return nil }

        let rateStat = robustStats(historyRates, floor: rateAbsoluteFloor)
        let rateSigma = (latestRate - rateStat.median) / rateStat.scale
        let rateIsAnomaly = abs(rateSigma) > sigmaThreshold

        // beat error 는 단방향(증가만 의미) — floor 적용.
        var beatSigma = 0.0
        var beatIsAnomaly = false
        if historyBeatErrors.count >= minHistoryCount {
            let beStat = robustStats(historyBeatErrors, floor: beatErrorAbsoluteFloor)
            beatSigma = (latestBeatError - beStat.median) / beStat.scale
            // 증가 방향만 이상으로 본다(beat error 감소는 개선).
            beatIsAnomaly = beatSigma > sigmaThreshold
        }

        // 두 축 모두 정상 → nil.
        guard rateIsAnomaly || beatIsAnomaly else { return nil }

        // 더 강한 신호를 사유로 채택.
        if rateIsAnomaly && abs(rateSigma) >= abs(beatSigma) {
            let reason: Reason = rateSigma > 0 ? .suspectMagnetization : .suspectShock
            return Anomaly(
                reason: reason,
                deviationSigma: rateSigma,
                latestRate: latestRate,
                baselineRate: rateStat.median
            )
        } else {
            return Anomaly(
                reason: .suspectBeatErrorSpike,
                deviationSigma: beatSigma,
                latestRate: latestRate,
                baselineRate: rateStat.median
            )
        }
    }

    // MARK: - Robust scale (median + MAD)

    private struct RobustStat { let median: Double; let scale: Double }

    /// 중앙값 + MAD→σ 환산 척도(1.4826). floor 로 하한을 둬 MAD≈0 시 0 나눗셈/과민반응 방지.
    private static func robustStats(_ values: [Double], floor: Double) -> RobustStat {
        let sorted = values.sorted()
        let median = medianOfSorted(sorted)
        let deviations = values.map { Swift.abs($0 - median) }.sorted()
        let mad = medianOfSorted(deviations)
        let scale = Swift.max(mad * 1.4826, floor)
        return RobustStat(median: median, scale: scale)
    }

    /// 정렬된 배열의 참 중앙값 — 짝수 개수면 두 중앙값 평균(기존 sorted[n/2] 는 짝수서 상위값 편향).
    private static func medianOfSorted(_ s: [Double]) -> Double {
        let n = s.count
        guard n > 0 else { return 0 }
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
}
