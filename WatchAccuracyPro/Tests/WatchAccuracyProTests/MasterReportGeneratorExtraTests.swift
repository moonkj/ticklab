import SwiftData
import UIKit
import XCTest
@testable import WatchAccuracyPro

/// MasterReportGenerator — ReportGeneratorTests 가 안 다루는 시계 페이지 분기.
///   · photoData 그리기 · nickname/referenceNumber/purchaseDate/warranty KV · manualCaliberTag 생략
///   · LAST MEASUREMENT 블록(측정 존재) · 가격 없는 includePrices 경로
/// 모두 유효 PDF(%PDF- 매직 헤더)를 크래시 없이 생성하는지 검증. @MainActor.
@MainActor
final class MasterReportGeneratorExtraTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([
            Watch.self, WatchMeasurement.self, SpecCard.self,
            WearLog.self, ServiceLog.self, JournalEntry.self
        ])
        container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    private func assertIsPDF(_ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(data.isEmpty, "PDF data should not be empty", file: file, line: line)
        XCTAssertEqual(data.prefix(5), Data("%PDF-".utf8),
                       "PDF should begin with %PDF- magic header", file: file, line: line)
    }

    /// 작은 단색 PNG (photoData 분기 커버용).
    private func tinyPNG() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        let img = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        return img.pngData() ?? Data()
    }

    func test_masterReport_watchWithPhotoNicknameAndDates() {
        let cal = Calendar.current
        let purchased = cal.date(from: DateComponents(year: 2022, month: 4, day: 10))!
        let watch = Watch(
            brand: "IWC", model: "Portugieser", caliber: "52010",
            purchaseDate: purchased, photoData: tinyPNG(),
            nickname: "데일리", referenceNumber: "IW500705",
            purchasePrice: 15_000_000, purchaseCurrency: "KRW",
            warrantyMonths: 24
        )
        context.insert(watch)
        try? context.save()

        let data = MasterReportGenerator.generate(watches: [watch], includePrices: true)
        assertIsPDF(data)
    }

    func test_masterReport_watchWithMeasurement_drawsLastMeasurementBlock() {
        let watch = Watch(brand: "Omega", model: "Speedmaster", caliber: "3861")
        context.insert(watch)
        let m = WatchMeasurement(
            watch: watch, rateSecondsPerDay: 4.2, beatErrorMs: 0.5,
            amplitudeDegrees: 290, bph: 21_600, confidenceScore: 88, durationSeconds: 30
        )
        context.insert(m)
        try? context.save()

        let data = MasterReportGenerator.generate(watches: [watch], includePrices: true)
        assertIsPDF(data)
    }

    func test_masterReport_manualCaliberTag_omitsCaliberRow() {
        let watch = Watch(brand: "Custom", model: "DIY", caliber: Watch.manualCaliberTag,
                          customBph: 28_800)
        context.insert(watch)
        try? context.save()

        let data = MasterReportGenerator.generate(watches: [watch], includePrices: true)
        assertIsPDF(data)
    }

    func test_masterReport_includePrices_butNoPriceSet_producesPDF() {
        // includePrices=true 이지만 purchasePrice nil → 총가치 분기(total>0) 미진입 경로.
        let watch = Watch(brand: "Seiko", model: "Presage")
        context.insert(watch)
        try? context.save()

        let data = MasterReportGenerator.generate(watches: [watch], includePrices: true)
        assertIsPDF(data)
    }

    func test_masterReport_manyWatches_coverTableRows() {
        // 다수 시계 → 커버 테이블 행 루프 반복 경로.
        var watches: [Watch] = []
        for i in 0..<6 {
            let w = Watch(brand: "Brand\(i)", model: "Model\(i)",
                          purchasePrice: Decimal(1_000_000 * (i + 1)), purchaseCurrency: "KRW")
            context.insert(w)
            watches.append(w)
        }
        try? context.save()

        let data = MasterReportGenerator.generate(watches: watches, includePrices: true)
        assertIsPDF(data)
    }
}
