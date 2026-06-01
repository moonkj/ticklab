import SwiftData
import XCTest
@testable import WatchAccuracyPro

/// DataExportService — DataExportServiceTests 가 안 다루는 분기.
///   · ExportFormat allCases/id/fileExtension/mimeType · 단일 watch export 오버로드
///   · ExportPayload.tempURL 파일 쓰기 · importWatches(garbage) → 0
@MainActor
final class DataExportServiceExtraTests: XCTestCase {
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

    // MARK: - ExportFormat enum

    func test_exportFormat_allCases_and_identifiable() {
        XCTAssertEqual(ExportFormat.allCases, [.csv, .json])
        XCTAssertEqual(ExportFormat.csv.id, "csv")
        XCTAssertEqual(ExportFormat.json.id, "json")
    }

    func test_exportFormat_fileExtension_and_mimeType() {
        XCTAssertEqual(ExportFormat.csv.fileExtension, "csv")
        XCTAssertEqual(ExportFormat.json.fileExtension, "json")
        XCTAssertEqual(ExportFormat.csv.mimeType, "text/csv")
        XCTAssertEqual(ExportFormat.json.mimeType, "application/json")
    }

    // MARK: - 단일 watch export 오버로드

    func test_single_watch_export_csv_delegates_to_array() {
        let ctx = container.mainContext
        let watch = Watch(brand: "Seiko", model: "SPB143", caliber: "6R35")
        ctx.insert(watch)
        try? ctx.save()
        let payload = DataExportService.export(watch: watch, format: .csv)
        let text = String(data: payload.data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.hasPrefix("timestamp,brand,model"))
        XCTAssertTrue(text.contains("Seiko"))
        XCTAssertEqual(payload.mimeType, "text/csv")
        XCTAssertTrue(payload.filename.hasSuffix(".csv"))
    }

    func test_single_watch_export_json_has_correct_extension() {
        let ctx = container.mainContext
        let watch = Watch(brand: "Oris", model: "Aquis")
        ctx.insert(watch)
        try? ctx.save()
        let payload = DataExportService.export(watch: watch, format: .json)
        XCTAssertEqual(payload.mimeType, "application/json")
        XCTAssertTrue(payload.filename.hasSuffix(".json"))
        XCTAssertFalse(payload.data.isEmpty)
    }

    // MARK: - ExportPayload.tempURL

    func test_tempURL_writes_file_to_disk() throws {
        let ctx = container.mainContext
        let watch = Watch(brand: "Tudor", model: "Pelagos")
        ctx.insert(watch)
        try? ctx.save()
        let payload = DataExportService.export(watch: watch, format: .csv)
        let url = try XCTUnwrap(payload.tempURL, "tempURL should produce a file URL")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let roundtrip = try Data(contentsOf: url)
        XCTAssertEqual(roundtrip, payload.data, "written bytes match payload data")
        XCTAssertEqual(url.lastPathComponent, payload.filename)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - import garbage / empty

    func test_importWatches_invalid_json_returns_zero() {
        let garbage = Data("not valid json at all".utf8)
        let count = DataExportService.importWatches(from: garbage, into: container.mainContext)
        XCTAssertEqual(count, 0)
    }

    func test_importWatches_empty_data_returns_zero() {
        let count = DataExportService.importWatches(from: Data(), into: container.mainContext)
        XCTAssertEqual(count, 0)
    }

    func test_importWatches_empty_collection_json_returns_zero() {
        // 유효 JSON 이지만 watches 가 비어 있으면 0 import.
        let empty = DataExportService.export(watches: [], format: .json)
        let count = DataExportService.importWatches(from: empty.data, into: container.mainContext)
        XCTAssertEqual(count, 0)
    }
}
