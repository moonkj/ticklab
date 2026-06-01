import XCTest
@testable import WatchAccuracyPro

/// TrendDiagnosisService.diagnose 의 룰 기반 severity 판정 검증.
/// 순수 함수: Watch + [WatchMeasurement] → Diagnosis?  (ModelContext 불필요).
/// 로컬라이즈 문자열 자체가 아니라 severity 분기 + 구조(비어있지 않은 headline/coaching)를 검증해
/// 로케일에 무관하게 통과하도록 한다.
@MainActor
final class TrendDiagnosisServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeMeasurement(
        rate: Double,
        beatError: Double = 0.2,
        position: Position = .unknown,
        secondsAgo: TimeInterval
    ) -> WatchMeasurement {
        WatchMeasurement(
            timestamp: Date().addingTimeInterval(-secondsAgo),
            rateSecondsPerDay: rate,
            beatErrorMs: beatError,
            amplitudeDegrees: nil,
            bph: 28800,
            confidenceScore: 90,
            durationSeconds: 30,
            metadata: MeasurementMetadata(position: position)
        )
    }

    private func makeWatch() -> Watch {
        Watch(brand: "Omega", model: "Speedmaster")
    }

    // MARK: - Guard: 측정 2회 미만 → nil

    func test_diagnose_returns_nil_for_fewer_than_two_measurements() {
        let watch = makeWatch()
        XCTAssertNil(TrendDiagnosisService.diagnose(watch: watch, measurements: []))
        XCTAssertNil(TrendDiagnosisService.diagnose(
            watch: watch,
            measurements: [makeMeasurement(rate: 2, secondsAgo: 100)]
        ))
    }

    // MARK: - severity = .good

    func test_diagnose_good_for_stable_small_rate() {
        let watch = makeWatch()
        // absAvg 작고(<=15), drift 작고(<=8), beatError 작음(<=0.5) → good.
        let ms = [
            makeMeasurement(rate: 2.0, beatError: 0.2, secondsAgo: 300),
            makeMeasurement(rate: 3.0, beatError: 0.2, secondsAgo: 200),
            makeMeasurement(rate: 2.5, beatError: 0.2, secondsAgo: 100),
        ]
        let d = TrendDiagnosisService.diagnose(watch: watch, measurements: ms)
        let diag = try! XCTUnwrap(d)
        XCTAssertEqual(diag.severity, .good)
        XCTAssertFalse(diag.headline.isEmpty)
        XCTAssertFalse(diag.coaching.isEmpty)
    }

    // MARK: - severity = .watch

    func test_diagnose_watch_for_moderate_rate() {
        let watch = makeWatch()
        // absAvg 20 (15<x<=30), drift 작음, beatError 작음 → watch (service 아님).
        let ms = [
            makeMeasurement(rate: 20.0, beatError: 0.2, secondsAgo: 300),
            makeMeasurement(rate: 20.0, beatError: 0.2, secondsAgo: 200),
            makeMeasurement(rate: 20.0, beatError: 0.2, secondsAgo: 100),
        ]
        let diag = try! XCTUnwrap(TrendDiagnosisService.diagnose(watch: watch, measurements: ms))
        XCTAssertEqual(diag.severity, .watch)
    }

    func test_diagnose_watch_for_large_drift() {
        let watch = makeWatch()
        // drift = last - first = 12 - 0 = 12 ( >8 ), absAvg 작게 유지(평균 6) → watch.
        let ms = [
            makeMeasurement(rate: 0.0, beatError: 0.2, secondsAgo: 300),
            makeMeasurement(rate: 6.0, beatError: 0.2, secondsAgo: 200),
            makeMeasurement(rate: 12.0, beatError: 0.2, secondsAgo: 100),
        ]
        let diag = try! XCTUnwrap(TrendDiagnosisService.diagnose(watch: watch, measurements: ms))
        XCTAssertEqual(diag.severity, .watch)
    }

    // MARK: - severity = .service

    func test_diagnose_service_for_high_average_rate() {
        let watch = makeWatch()
        // absAvg 40 ( >30 ) → service.
        let ms = [
            makeMeasurement(rate: 40.0, beatError: 0.2, secondsAgo: 300),
            makeMeasurement(rate: 40.0, beatError: 0.2, secondsAgo: 200),
            makeMeasurement(rate: 40.0, beatError: 0.2, secondsAgo: 100),
        ]
        let diag = try! XCTUnwrap(TrendDiagnosisService.diagnose(watch: watch, measurements: ms))
        XCTAssertEqual(diag.severity, .service)
    }

    func test_diagnose_service_for_high_beat_error() {
        let watch = makeWatch()
        // avgBeatError 1.5 ( >1.0 ) → service, rate 는 작게 유지.
        let ms = [
            makeMeasurement(rate: 2.0, beatError: 1.5, secondsAgo: 300),
            makeMeasurement(rate: 2.0, beatError: 1.5, secondsAgo: 200),
            makeMeasurement(rate: 2.0, beatError: 1.5, secondsAgo: 100),
        ]
        let diag = try! XCTUnwrap(TrendDiagnosisService.diagnose(watch: watch, measurements: ms))
        XCTAssertEqual(diag.severity, .service)
    }

    func test_diagnose_service_for_high_positional_delta() {
        let watch = makeWatch()
        // 두 자세의 평균 rate 차이가 20 ( >=15 ) → service.
        let ms = [
            makeMeasurement(rate: 0.0, beatError: 0.2, position: .dialUp, secondsAgo: 400),
            makeMeasurement(rate: 0.0, beatError: 0.2, position: .dialUp, secondsAgo: 300),
            makeMeasurement(rate: 20.0, beatError: 0.2, position: .crownDown, secondsAgo: 200),
            makeMeasurement(rate: 20.0, beatError: 0.2, position: .crownDown, secondsAgo: 100),
        ]
        let diag = try! XCTUnwrap(TrendDiagnosisService.diagnose(watch: watch, measurements: ms))
        XCTAssertEqual(diag.severity, .service)
    }

    // MARK: - 순서 무관 (timestamp 정렬)

    func test_diagnose_sorts_by_timestamp_regardless_of_input_order() {
        let watch = makeWatch()
        let unsorted = [
            makeMeasurement(rate: 40.0, secondsAgo: 100),
            makeMeasurement(rate: 40.0, secondsAgo: 300),
            makeMeasurement(rate: 40.0, secondsAgo: 200),
        ]
        let diag = try! XCTUnwrap(TrendDiagnosisService.diagnose(watch: watch, measurements: unsorted))
        // 평균 40 → service. 입력 순서와 무관하게 동일.
        XCTAssertEqual(diag.severity, .service)
    }
}
