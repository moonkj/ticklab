import XCTest
@testable import WatchAccuracyPro

/// 스트림 D: `RateForecastService` 순수 함수 회귀 보호.
/// OLS 기울기·외삽·신뢰폭·minCount 게이트·정렬 무관성을 검증한다. 네트워크/시간 의존 없음.
final class RateForecastTests: XCTestCase {

    private let day: TimeInterval = 86_400

    /// 기준 시각 t0 에서 dayOffsets 일 만큼 떨어진 (Date, rate) 점 생성.
    private func points(t0: Date, dayOffsets: [Double], rates: [Double]) -> [(Date, Double)] {
        zip(dayOffsets, rates).map { (t0.addingTimeInterval($0 * day), $1) }
    }

    // MARK: - minCount 게이트

    func test_below_min_count_returns_nil() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = points(t0: t0, dayOffsets: [0, 1, 2], rates: [1, 2, 3])  // 3 < 4
        XCTAssertNil(RateForecastService.forecast(points: pts))
    }

    func test_exactly_min_count_returns_value() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = points(t0: t0, dayOffsets: [0, 1, 2, 3], rates: [0, 1, 2, 3])
        XCTAssertNotNil(RateForecastService.forecast(points: pts, minCount: 4))
    }

    func test_custom_min_count_respected() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts = points(t0: t0, dayOffsets: [0, 1, 2], rates: [0, 1, 2])
        XCTAssertNotNil(RateForecastService.forecast(points: pts, minCount: 3))
    }

    // MARK: - 완벽 선형 → slope/외삽 정확 복원

    func test_perfect_linear_slope_recovered() {
        // rate = 2 + 0.5·day → slope 0.5 s/d per day.
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let offs = [0.0, 10, 20, 30, 40]
        let rates = offs.map { 2.0 + 0.5 * $0 }
        let f = RateForecastService.forecast(points: points(t0: t0, dayOffsets: offs, rates: rates))!
        XCTAssertEqual(f.slopePerDay, 0.5, accuracy: 1e-9)
        // 마지막 측정 day=40 → currentRate = 2 + 0.5·40 = 22.
        XCTAssertEqual(f.currentRate, 22, accuracy: 1e-6)
        // +90일 외삽 → 2 + 0.5·130 = 67.
        XCTAssertEqual(f.projectedRate, 67, accuracy: 1e-6)
        // 완벽 직선 → 잔차 0 → 신뢰폭 0.
        XCTAssertEqual(f.confidenceMargin, 0, accuracy: 1e-9)
        XCTAssertEqual(f.sampleCount, 5)
        XCTAssertEqual(f.horizonDays, 90)
    }

    func test_horizon_parameter_changes_projection() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let offs = [0.0, 10, 20, 30]
        let rates = offs.map { 1.0 * $0 }  // slope 1, intercept 0.
        let f30 = RateForecastService.forecast(points: points(t0: t0, dayOffsets: offs, rates: rates), horizonDays: 30)!
        // last day=30 → current 30, +30 → 60.
        XCTAssertEqual(f30.projectedRate, 60, accuracy: 1e-6)
        XCTAssertEqual(f30.horizonDays, 30)
    }

    // MARK: - 정렬 무관성

    func test_reverse_ordered_input_gives_same_result() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let offs = [0.0, 5, 10, 15, 20]
        let rates: [Double] = [3, 4, 6, 7, 9]
        let asc = points(t0: t0, dayOffsets: offs, rates: rates)
        let desc = Array(asc.reversed())
        let fa = RateForecastService.forecast(points: asc)!
        let fd = RateForecastService.forecast(points: desc)!
        XCTAssertEqual(fa.slopePerDay, fd.slopePerDay, accuracy: 1e-9)
        XCTAssertEqual(fa.projectedRate, fd.projectedRate, accuracy: 1e-9)
        XCTAssertEqual(fa.currentRate, fd.currentRate, accuracy: 1e-9)
    }

    // MARK: - 신뢰폭(잔차 SD) > 0 when noisy

    func test_noisy_data_has_positive_margin() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let offs = [0.0, 1, 2, 3, 4, 5]
        // 추세 0 근처지만 흩어짐 → 잔차 SD > 0.
        let rates: [Double] = [-5, 6, -4, 5, -6, 4]
        let f = RateForecastService.forecast(points: points(t0: t0, dayOffsets: offs, rates: rates))!
        XCTAssertGreaterThan(f.confidenceMargin, 0)
        XCTAssertEqual(f.projectedUpperBound - f.projectedRate, f.confidenceMargin, accuracy: 1e-9)
        XCTAssertEqual(f.projectedRate - f.projectedLowerBound, f.confidenceMargin, accuracy: 1e-9)
    }

    // MARK: - span 0 (모든 측정 같은 시각) → nil

    func test_all_same_timestamp_returns_nil() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let pts: [(Date, Double)] = [(t0, 1), (t0, 2), (t0, 3), (t0, 4)]
        XCTAssertNil(RateForecastService.forecast(points: pts))
    }

    // MARK: - 음의 기울기 (점점 느려짐)

    func test_negative_slope() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let offs = [0.0, 10, 20, 30]
        let rates = offs.map { 10.0 - 0.3 * $0 }  // slope -0.3.
        let f = RateForecastService.forecast(points: points(t0: t0, dayOffsets: offs, rates: rates))!
        XCTAssertEqual(f.slopePerDay, -0.3, accuracy: 1e-9)
        // last day=30 → 10 - 9 = 1, +90 → day 120 → 10 - 36 = -26.
        XCTAssertEqual(f.projectedRate, -26, accuracy: 1e-6)
    }
}
