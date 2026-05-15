import XCTest
@testable import WatchAccuracyPro

final class SharedSnapshotStoreTests: XCTestCase {
    func test_round_trip_via_codable() {
        let snapshot = LatestMeasurementSnapshot(
            watchName: "Hamilton Khaki",
            caliber: "ETA_2824-2",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            rateSecondsPerDay: 2.5,
            beatErrorMs: 0.3,
            amplitudeDegrees: 285,
            bph: 28800,
            confidenceScore: 88
        )
        let data = try! JSONEncoder().encode(snapshot)
        let decoded = try! JSONDecoder().decode(LatestMeasurementSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func test_placeholder_is_well_formed() {
        let p = LatestMeasurementSnapshot.placeholder
        XCTAssertEqual(p.watchName, "TickLab")
        XCTAssertEqual(p.bph, 28800)
    }
}
