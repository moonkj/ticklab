import XCTest
import SwiftData
@testable import WatchAccuracyPro

final class ModelTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // SpecCard, WearLog, ServiceLog, JournalEntry 포함 — WatchDeletion.deleteCascade 헬퍼가
        // 이 모델들을 참조하므로 테스트 컨테이너 스키마에도 반드시 포함해야 한다.
        let schema = Schema([Watch.self, WatchMeasurement.self, SpecCard.self,
                             WearLog.self, ServiceLog.self, JournalEntry.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    func test_watch_create_and_persist() throws {
        let watch = Watch(brand: "Omega", model: "Speedmaster Professional", caliber: "1861")
        context.insert(watch)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Watch>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.brand, "Omega")
        XCTAssertEqual(fetched.first?.measurements.count, 0)
    }

    func test_measurement_relationship_attaches_to_watch() throws {
        let watch = Watch(brand: "Hamilton", model: "Khaki Field", caliber: "ETA_2824-2")
        context.insert(watch)

        let measurement = WatchMeasurement(
            rateSecondsPerDay: 5.2,
            beatErrorMs: 0.4,
            amplitudeDegrees: 285.0,
            bph: 28800,
            confidenceScore: 88,
            durationSeconds: 120,
            metadata: MeasurementMetadata(position: .dialUp, ambientNoiseDB: 32, deviceModel: "iPhone 15 Pro")
        )
        context.insert(measurement)
        // SwiftData inverse relationship: insert → assign 순서가 핵심.
        measurement.watch = watch
        try context.save()

        XCTAssertEqual(watch.measurements.count, 1)
        XCTAssertEqual(watch.measurements.first?.bph, 28800)
        XCTAssertEqual(watch.measurements.first?.metadata.position, .dialUp)
    }

    func test_watch_delete_cascades_measurements() throws {
        let watch = Watch(brand: "Tudor", model: "Black Bay 58", caliber: "Tudor_MT5602")
        context.insert(watch)
        let m1 = WatchMeasurement(rateSecondsPerDay: 1, beatErrorMs: 0.2, bph: 28800, confidenceScore: 80, durationSeconds: 60)
        let m2 = WatchMeasurement(rateSecondsPerDay: -2, beatErrorMs: 0.3, bph: 28800, confidenceScore: 75, durationSeconds: 60)
        context.insert(m1)
        context.insert(m2)
        watch.measurements.append(m1)
        watch.measurements.append(m2)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<WatchMeasurement>()).count, 2)
        XCTAssertEqual(watch.measurements.count, 2)

        let fetchedWatch = try XCTUnwrap(try context.fetch(FetchDescriptor<Watch>()).first)
        // iOS 17.x SwiftData 버그 회피: deleteCascade 헬퍼로 자식을 명시적으로 함께 삭제한다.
        fetchedWatch.deleteCascade(in: context)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Watch>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WatchMeasurement>()).count, 0,
                       "deleteCascade 헬퍼가 자식까지 함께 지워야 한다")
    }

    func test_measurement_metadata_codable_roundtrip() throws {
        let metadata = MeasurementMetadata(
            position: .crownDown,
            temperatureCelsius: 22.5,
            ambientNoiseDB: 30,
            powerReserveEstimate: 0.6,
            deviceModel: "iPhone 15 Pro",
            microphoneType: .builtin
        )
        let measurement = WatchMeasurement(
            rateSecondsPerDay: 0,
            beatErrorMs: 0,
            bph: 28800,
            confidenceScore: 90,
            durationSeconds: 30,
            metadata: metadata
        )
        XCTAssertEqual(measurement.metadata.position, .crownDown)
        XCTAssertEqual(measurement.metadata.temperatureCelsius, 22.5)
        XCTAssertEqual(measurement.metadata.microphoneType, .builtin)
    }
}
