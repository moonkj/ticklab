import Foundation

/// Round 171 (사용자 실측 결정): 단일 측정은 자세·커플링 차이로 ±10~15 s/d 변동이 물리적으로 불가피.
/// "매번 같은 숫자"는 알고리즘이 아니라 **다회 측정 평균**으로 얻는다 (전문 타이밍의 표준).
/// 최근 측정 rate 들의 신뢰 대표값과 변동 폭을 계산하는 순수 로직.
///
/// 사용자 요구: "차이가 많이 나는 데이터는 평균에서 제외" — 단순 trim 이 아니라
/// **중앙값(median) 기준 MAD outlier 제거**로 −12.1 같은 동떨어진 측정을 평균에서 뺀다.
enum RateAggregate {

    struct Trusted: Equatable {
        /// outlier 제거 후 평균 rate (s/d) — 대표 신뢰값.
        let meanRate: Double
        /// 측정 간 변동 폭(전체 표본 표준편차, s/d) — 제거 전 기준이라 "실제 얼마나 흩어졌나" 정직 표시.
        let spread: Double
        /// 입력된 전체 측정 수.
        let count: Int
        /// outlier 로 제외된 측정 수.
        let excluded: Int
    }

    /// 최근 측정 rate 배열의 신뢰 대표값.
    /// - Parameters:
    ///   - rates: 최근 측정 rate (정렬 무관, 보통 최신 N개).
    ///   - minCount: 이 수 미만이면 nil (소수 측정은 평균 의미 약함).
    ///   - outlierK: 중앙값에서 `outlierK × σ(=MAD×1.4826)` 초과로 벗어난 측정을 제외. floor 5 s/d.
    /// - Returns: outlier 제거 후 평균 + 전체 변동 폭. (제거가 과하면 전체 사용 — fail-safe)
    static func trusted(rates: [Double], minCount: Int = 3, outlierK: Double = 3.0) -> Trusted? {
        guard rates.count >= minCount else { return nil }
        let sorted = rates.sorted()
        let median = sorted[sorted.count / 2]
        // MAD = median(|xᵢ − median|), σ 환산 1.4826. 임계 = max(k·σ, 절대 floor 5 s/d).
        // floor: MAD 가 0/작아도(거의 일치) 5 s/d 이내는 outlier 로 보지 않음 — 정상 변동 보존.
        let deviations = rates.map { Swift.abs($0 - median) }.sorted()
        let mad = deviations[deviations.count / 2]
        let threshold = Swift.max(outlierK * mad * 1.4826, 5.0)
        let kept = rates.filter { Swift.abs($0 - median) <= threshold }
        // 너무 많이 걸러지면(절반 이상) outlier 판정 신뢰 어려움 → 전체 사용.
        let used = kept.count >= Swift.max(2, rates.count / 2) ? kept : rates
        let mean = used.reduce(0, +) / Double(used.count)
        // spread 는 제거 전 전체 변동 — 사용자에게 흩어짐을 정직하게 보여줌.
        let allMean = rates.reduce(0, +) / Double(rates.count)
        let variance = rates.map { ($0 - allMean) * ($0 - allMean) }.reduce(0, +) / Double(rates.count)
        return Trusted(
            meanRate: mean,
            spread: variance.squareRoot(),
            count: rates.count,
            excluded: rates.count - used.count
        )
    }
}
