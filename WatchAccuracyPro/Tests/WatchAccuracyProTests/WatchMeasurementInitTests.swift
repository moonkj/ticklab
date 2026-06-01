import XCTest
import SwiftData
@testable import WatchAccuracyPro

/// WatchMeasurement — 스칼라 init 기본값 + metadata 인코딩 getter/setter 라운드트립.
/// `watch` 관계(relationship)에는 접근하지 않으므로 ModelContext 불필요(스칼라만 사용).
/// ModelTests 가 다루지 않는 init 기본값/Identifiable/setter 경로만 커버.
final class WatchMeasurementInitTests: XCTestCase {

    func test_init_defaults_are_applied() {
        let m = WatchMeasurement(
            rateSecondsPerDay: 2.0, beatErrorMs: 0.3,
            bph: 28_800, confidenceScore: 80, durationSeconds: 30
        )
        XCTAssertNil(m.watch, "watch 기본값 nil")
        XCTAssertNil(m.amplitudeDegrees, "amplitude 기본값 nil")
        XCTAssertNil(m.notes, "notes 기본값 nil")
        XCTAssertEqual(m.bph, 28_800)
        XCTAssertEqual(m.confidenceScore, 80)
        XCTAssertEqual(m.durationSeconds, 30)
        XCTAssertEqual(m.rateSecondsPerDay, 2.0, accuracy: 1e-9)
        XCTAssertEqual(m.beatErrorMs, 0.3, accuracy: 1e-9)
        // 기본 timestamp 는 init 시점(now) 근처.
        XCTAssertEqual(m.timestamp.timeIntervalSinceNow, 0, accuracy: 5)
    }

    func test_init_generates_unique_ids() {
        let a = WatchMeasurement(rateSecondsPerDay: 0, beatErrorMs: 0,
                                 bph: 21_600, confidenceScore: 50, durationSeconds: 30)
        let b = WatchMeasurement(rateSecondsPerDay: 0, beatErrorMs: 0,
                                 bph: 21_600, confidenceScore: 50, durationSeconds: 30)
        XCTAssertNotEqual(a.id, b.id, "id 기본값은 매번 새 UUID")
    }

    func test_init_explicit_id_is_preserved() {
        let id = UUID()
        let m = WatchMeasurement(id: id, rateSecondsPerDay: 1, beatErrorMs: 0.1,
                                 bph: 28_800, confidenceScore: 70, durationSeconds: 60)
        XCTAssertEqual(m.id, id)
    }

    func test_init_explicit_optionals_preserved() {
        let m = WatchMeasurement(
            rateSecondsPerDay: -3.5, beatErrorMs: 0.4, amplitudeDegrees: 275,
            bph: 28_800, confidenceScore: 92, durationSeconds: 45, notes: "dial up 측정"
        )
        XCTAssertEqual(m.amplitudeDegrees, 275)
        XCTAssertEqual(m.notes, "dial up 측정")
    }

    // MARK: - metadata getter/setter (JSON 인코딩 라운드트립)

    func test_metadata_init_roundtrips_through_getter() {
        let meta = MeasurementMetadata(position: .crownUp, temperatureCelsius: 21.0,
                                       ambientNoiseDB: 30, snrDB: 18,
                                       deviceModel: "iPhone16,1", microphoneType: .wired)
        let m = WatchMeasurement(rateSecondsPerDay: 1, beatErrorMs: 0.2,
                                 bph: 28_800, confidenceScore: 80, durationSeconds: 30,
                                 metadata: meta)
        XCTAssertEqual(m.metadata, meta, "init 으로 인코딩한 metadata 가 getter 로 동일하게 디코딩")
        XCTAssertEqual(m.metadata.position, .crownUp)
        XCTAssertEqual(m.metadata.microphoneType, .wired)
        XCTAssertEqual(m.metadata.snrDB, 18)
    }

    func test_metadata_setter_then_getter_roundtrip() {
        let m = WatchMeasurement(rateSecondsPerDay: 0, beatErrorMs: 0,
                                 bph: 21_600, confidenceScore: 60, durationSeconds: 30)
        // 기본 init metadata 는 default — setter 로 교체 후 getter 일치 확인.
        var updated = MeasurementMetadata()
        updated.position = .dialDown
        updated.ambientNoiseDB = 42
        updated.deviceModel = "iPhone15,3"
        m.metadata = updated
        XCTAssertEqual(m.metadata, updated)
        XCTAssertEqual(m.metadata.position, .dialDown)
        XCTAssertEqual(m.metadata.ambientNoiseDB, 42)
    }

    func test_default_metadata_is_decodable_default() {
        let m = WatchMeasurement(rateSecondsPerDay: 0, beatErrorMs: 0,
                                 bph: 28_800, confidenceScore: 50, durationSeconds: 30)
        // 기본 metadata == MeasurementMetadata() (position .unknown).
        XCTAssertEqual(m.metadata.position, .unknown)
        XCTAssertEqual(m.metadata.ambientNoiseDB, 0)
        XCTAssertEqual(m.metadata.microphoneType, .builtin)
    }
}
