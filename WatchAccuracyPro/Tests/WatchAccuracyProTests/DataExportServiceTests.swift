import SwiftData
import XCTest
@testable import WatchAccuracyPro

@MainActor
final class DataExportServiceTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        let schema = Schema([
            Watch.self, WatchMeasurement.self, WearLog.self,
            JournalEntry.self, SpecCard.self, ServiceLog.self
        ])
        container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    override func tearDownWithError() throws {
        container = nil
    }

    private func makeFixture() -> Watch {
        let ctx = container.mainContext
        let watch = Watch(brand: "Hamilton", model: "Khaki Field", caliber: "ETA_2824-2")
        ctx.insert(watch)
        let m1 = WatchMeasurement(
            rateSecondsPerDay: 2.5, beatErrorMs: 0.3, amplitudeDegrees: 280,
            bph: 28800, confidenceScore: 85, durationSeconds: 30,
            metadata: MeasurementMetadata(position: .dialUp, ambientNoiseDB: 24,
                                          deviceModel: "iPhone15,3", microphoneType: .builtin)
        )
        m1.watch = watch
        ctx.insert(m1)
        let m2 = WatchMeasurement(
            rateSecondsPerDay: -1.1, beatErrorMs: 0.2, amplitudeDegrees: 285,
            bph: 28800, confidenceScore: 90, durationSeconds: 60,
            metadata: MeasurementMetadata(position: .crownDown, ambientNoiseDB: 22,
                                          deviceModel: "iPhone15,3", microphoneType: .bluetooth)
        )
        m2.watch = watch
        ctx.insert(m2)
        try? ctx.save()
        return watch
    }

    func test_csv_export_has_header_and_rows() {
        let watch = makeFixture()
        let payload = DataExportService.export(watches: [watch], format: .csv)
        let text = String(data: payload.data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.hasPrefix("timestamp,brand,model"))
        XCTAssertTrue(text.contains("Hamilton"))
        XCTAssertTrue(text.contains("Khaki Field"))
        XCTAssertTrue(text.contains("28800"))
        let lines = text.components(separatedBy: "\r\n")
        XCTAssertEqual(lines.count, 3)
    }

    func test_csv_header_includes_round115_fields() {
        let watch = makeFixture()
        let payload = DataExportService.export(watches: [watch], format: .csv)
        let text = String(data: payload.data, encoding: .utf8) ?? ""
        let header = text.components(separatedBy: "\r\n").first ?? ""
        XCTAssertTrue(header.contains("nickname"), "CSV header must include nickname column")
        XCTAssertTrue(header.contains("reference_number"), "CSV header must include reference_number column")
    }

    func test_csv_escapes_quotes_and_commas() {
        let ctx = container.mainContext
        let watch = Watch(brand: "Brand, with comma", model: "Model \"quoted\"")
        ctx.insert(watch)
        let m = WatchMeasurement(
            rateSecondsPerDay: 0, beatErrorMs: 0, bph: 28800,
            confidenceScore: 50, durationSeconds: 30
        )
        m.watch = watch
        ctx.insert(m)
        try? ctx.save()
        let payload = DataExportService.export(watches: [watch], format: .csv)
        let text = String(data: payload.data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("\"Brand, with comma\""))
        XCTAssertTrue(text.contains("\"Model \"\"quoted\"\"\""))
    }

    func test_json_export_is_valid_and_decodable() throws {
        let watch = makeFixture()
        let payload = DataExportService.export(watches: [watch], format: .json)
        let any = try JSONSerialization.jsonObject(with: payload.data) as? [String: Any]
        XCTAssertNotNil(any?["watches"])
        XCTAssertNotNil(any?["exportedAt"])
        let watches = any?["watches"] as? [[String: Any]]
        XCTAssertEqual(watches?.count, 1)
        XCTAssertEqual(watches?.first?["brand"] as? String, "Hamilton")
    }
}
