import XCTest
@testable import WatchAccuracyPro

/// Round 171 다회 측정 평균(신뢰 대표값) + MAD outlier 제거 순수 로직 회귀 보호.
final class RateAggregateTests: XCTestCase {

    func test_belowMinCount_returnsNil() {
        XCTAssertNil(RateAggregate.trusted(rates: [1.0, 2.0]))               // 2 < 3
        XCTAssertNil(RateAggregate.trusted(rates: [5.0], minCount: 3))
    }

    func test_consistentMeasurements_noneExcluded_smallSpread() {
        let t = RateAggregate.trusted(rates: [1.0, 1.2, 0.8, 1.1, 0.9])
        XCTAssertEqual(t?.meanRate ?? .nan, 1.0, accuracy: 0.3)
        XCTAssertEqual(t?.excluded, 0, "일관 측정은 제외 0")
        XCTAssertLessThan(t?.spread ?? .infinity, 1.0, "일관 측정은 spread 작음")
    }

    func test_excludesFarOutlier_realWorld() {
        // 실측 유사: +5.7 / -12.1 / +1.4 / +3.0 → -12.1 은 중앙값에서 크게 벗어남 → 제외.
        let t = RateAggregate.trusted(rates: [5.7, -12.1, 1.4, 3.0])
        XCTAssertEqual(t?.excluded, 1, "-12.1 outlier 1개 제외")
        // 제외 후 평균은 다수값(+1~+6) 근처 — -12.1 에 끌려가지 않음.
        XCTAssertGreaterThan(t?.meanRate ?? .nan, 0, "outlier 제외 → 평균이 음수로 안 끌려감")
        XCTAssertLessThan(t?.meanRate ?? .nan, 6, "다수값 범위 내")
    }

    func test_grossOutlier_excludedButSpreadReflectsIt() {
        let t = RateAggregate.trusted(rates: [2.0, 3.0, 2.5, -40.0, 2.8])
        XCTAssertEqual(t?.excluded, 1, "-40 제외")
        XCTAssertEqual(t?.meanRate ?? .nan, 2.575, accuracy: 0.3, "제외 후 평균은 다수값 근처")
        XCTAssertGreaterThan(t?.spread ?? 0, 10, "spread 는 제거 전 기준 → 흩어짐 정직 표시")
    }

    func test_tightTriple_withinFloor_noneExcluded() {
        // 3개, 중앙값 floor(5 s/d) 안 → 제외 없음, 단순 평균.
        let t = RateAggregate.trusted(rates: [2.0, 4.0, 6.0])
        XCTAssertEqual(t?.meanRate ?? .nan, 4.0, accuracy: 0.001)
        XCTAssertEqual(t?.excluded, 0)
        XCTAssertEqual(t?.count, 3)
    }

    func test_doesNotOverTrim_whenMajorityScattered() {
        // 절반 이상이 흩어지면 outlier 판정 불가 → 전체 사용(fail-safe), 제외 0.
        let t = RateAggregate.trusted(rates: [-30.0, 30.0, -28.0, 29.0])
        XCTAssertEqual(t?.excluded, 0, "다수가 흩어지면 무리하게 제거하지 않음")
    }
}
