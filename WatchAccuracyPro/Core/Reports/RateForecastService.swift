import Foundation

/// 스트림 D: Rate Drift 예측.
///
/// 한 시계의 측정 (timestamp, rateSecondsPerDay) 시계열에 **OLS 선형회귀**(ClockCalibrationService.regressionPpm
/// 의 최소제곱 패턴과 동일 골격)를 적용해 추세 기울기(s/d per day)·N일 외삽값·잔차 기반 신뢰구간을 산출한다.
///
/// 핵심 로직은 `[(Date, Double)]` 입력의 **순수 함수**(`forecast(points:...)`)로 분리해 단위 테스트가 가능하다.
/// on-device·외부 전송 0. 측정 ≥ `minCount` 일 때만 값을 반환(데이터 부족 시 graceful degrade → nil).
enum RateForecastService {

    /// 예측 결과. 모든 rate 값은 s/d.
    struct Forecast: Equatable {
        /// 추세 기울기 — 하루당 rate 변화량 (s/d per day). +면 점점 빨라짐(rate 증가).
        let slopePerDay: Double
        /// 회귀선이 가리키는 "지금"(마지막 측정 시각)의 rate (s/d). 외삽 anchor.
        let currentRate: Double
        /// `horizonDays` 일 뒤 외삽 rate (s/d).
        let projectedRate: Double
        /// projectedRate 의 ± 신뢰폭 (s/d, 잔차 표준편차 기반). 작을수록 신뢰.
        let confidenceMargin: Double
        /// 외삽 지평(일).
        let horizonDays: Int
        /// 회귀에 사용된 측정 수.
        let sampleCount: Int

        /// 예측 구간 하한.
        var projectedLowerBound: Double { projectedRate - confidenceMargin }
        /// 예측 구간 상한.
        var projectedUpperBound: Double { projectedRate + confidenceMargin }
    }

    /// 기본 외삽 지평 — 90일.
    static let defaultHorizonDays = 90
    /// 최소 측정 수. 미만이면 추세 의미가 약해 nil.
    static let defaultMinCount = 4

    /// WatchMeasurement 배열에서 예측 산출. (timestamp, rate)로 매핑 후 순수 함수 호출.
    /// - Note: 신뢰도 라벨 존중은 caller(서비스 게이트) 책임 — medium/low 캘리버는 amplitude 만 숨기면 되고
    ///   rate 추세 자체는 표시 가능. (Hard Rule 9 는 amplitude 한정.)
    static func forecast(
        measurements: [WatchMeasurement],
        horizonDays: Int = defaultHorizonDays,
        minCount: Int = defaultMinCount
    ) -> Forecast? {
        let points = measurements.map { ($0.timestamp, $0.rateSecondsPerDay) }
        return forecast(points: points, horizonDays: horizonDays, minCount: minCount)
    }

    /// 순수 함수 핵심 — `[(Date, Double)]` 입력. 테스트 가능.
    /// 모델: rate ≈ a + slope·(elapsedDays). OLS 로 a·slope 추정 → 마지막 점 기준 horizon 외삽.
    /// 신뢰폭 = 잔차 표준편차(residual SD). 점이 회귀선에 잘 붙을수록 좁다.
    /// - Returns: 측정 < minCount 이거나 시간 span 이 0(전부 같은 시각)이면 nil.
    static func forecast(
        points: [(Date, Double)],
        horizonDays: Int = defaultHorizonDays,
        minCount: Int = defaultMinCount
    ) -> Forecast? {
        guard points.count >= minCount else { return nil }
        // 시간순 정렬 — 입력이 reverse 정렬돼 들어와도 안전.
        let sorted = points.sorted { $0.0 < $1.0 }

        // x = 첫 측정 기준 경과 "일". 큰 unix 초 대신 days 스케일 → 수치 안정 + slope 단위 직관(s/d per day).
        let t0 = sorted.first!.0.timeIntervalSince1970
        let xs = sorted.map { ($0.0.timeIntervalSince1970 - t0) / 86_400.0 }
        let ys = sorted.map { $0.1 }
        let n = Double(xs.count)

        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for i in xs.indices {
            let dx = xs[i] - meanX
            num += dx * (ys[i] - meanY)
            den += dx * dx
        }
        // span 0(모든 측정이 같은 시각) → 기울기 정의 불가.
        guard den > 0 else { return nil }

        let slope = num / den              // s/d per day
        let intercept = meanY - slope * meanX

        // 잔차 표준편차 — 회귀선 fit 의 정직한 산포. (불편추정: n-2 자유도, n=2 면 0 으로 처리.)
        var ssr = 0.0
        for i in xs.indices {
            let fit = intercept + slope * xs[i]
            let r = ys[i] - fit
            ssr += r * r
        }
        let dof = max(1.0, n - 2.0)
        let residualSD = (ssr / dof).squareRoot()

        let lastX = xs.last!
        let currentRate = intercept + slope * lastX
        let projectedX = lastX + Double(horizonDays)
        let projectedRate = intercept + slope * projectedX

        return Forecast(
            slopePerDay: slope,
            currentRate: currentRate,
            projectedRate: projectedRate,
            confidenceMargin: residualSD,
            horizonDays: horizonDays,
            sampleCount: xs.count
        )
    }
}
