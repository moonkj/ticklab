import XCTest
import SwiftData
@testable import WatchAccuracyPro

/// Cluster: REPORT / TEXT / CSV GENERATORS (pure output from model data).
/// 대상: ConditionReportGenerator, MasterReportGenerator (PDF Data),
///       CollectionGalleryGenerator (HTML), CollectionShareCardGenerator (PNG),
///       WrappedReportData (순수 데이터 집계).
@MainActor
final class ReportGeneratorTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([
            Watch.self, WatchMeasurement.self, SpecCard.self,
            WearLog.self, ServiceLog.self, JournalEntry.self,
            Strap.self, WatchPhoto.self
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

    // MARK: - Fixtures

    private func makeWatch(
        brand: String = "Omega",
        model: String = "Speedmaster",
        caliber: String? = "1861",
        price: Decimal? = 8_000_000,
        currency: String? = "KRW"
    ) -> Watch {
        let watch = Watch(brand: brand, model: model, caliber: caliber,
                          purchasePrice: price, purchaseCurrency: currency)
        context.insert(watch)
        return watch
    }

    @discardableResult
    private func addMeasurement(
        to watch: Watch,
        rate: Double = 3.2,
        beatError: Double = 0.4,
        confidence: Int = 88,
        timestamp: Date = Date()
    ) -> WatchMeasurement {
        let m = WatchMeasurement(
            watch: watch,
            timestamp: timestamp,
            rateSecondsPerDay: rate,
            beatErrorMs: beatError,
            amplitudeDegrees: 280,
            bph: 21600,
            confidenceScore: confidence,
            durationSeconds: 30
        )
        context.insert(m)
        return m
    }

    /// PDF Data 유효성: %PDF- 매직 헤더 + 비어있지 않음.
    private func assertIsPDF(_ data: Data, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(data.isEmpty, "PDF data should not be empty", file: file, line: line)
        let prefix = data.prefix(5)
        XCTAssertEqual(prefix, Data("%PDF-".utf8), "PDF should begin with %PDF- magic header", file: file, line: line)
    }

    // MARK: - ConditionReportGenerator

    func test_conditionReport_generatesValidPDF() {
        let watch = makeWatch()
        let m = addMeasurement(to: watch)
        try? context.save()

        let data = ConditionReportGenerator.generate(for: watch, measurements: [m])
        assertIsPDF(data)
    }

    func test_conditionReport_withNoMeasurements_stillProducesPDF() {
        let watch = makeWatch(price: nil, currency: nil)
        try? context.save()

        let data = ConditionReportGenerator.generate(for: watch, measurements: [])
        assertIsPDF(data)
    }

    func test_conditionReport_manualCaliberTag_doesNotCrash() {
        // caliber == manualCaliberTag 분기(스펙 섹션에서 캘리버 생략) 커버.
        let watch = makeWatch(caliber: Watch.manualCaliberTag)
        try? context.save()

        let data = ConditionReportGenerator.generate(for: watch, measurements: [])
        assertIsPDF(data)
    }

    func test_conditionReport_withManyMeasurements_limitsToRecentFive() {
        // 측정 7건 → 최근 5건만 그려지는 경로 실행 (크래시 없이 PDF 생성).
        let watch = makeWatch()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var measurements: [WatchMeasurement] = []
        for i in 0..<7 {
            measurements.append(addMeasurement(
                to: watch,
                rate: Double(i),
                confidence: 70 + i,
                timestamp: base.addingTimeInterval(Double(i) * 86_400)
            ))
        }
        try? context.save()

        let data = ConditionReportGenerator.generate(for: watch, measurements: measurements)
        assertIsPDF(data)
    }

    // MARK: - MasterReportGenerator

    func test_masterReport_emptyCollection_producesCoverOnlyPDF() {
        let data = MasterReportGenerator.generate(watches: [])
        assertIsPDF(data)
    }

    func test_masterReport_withWatches_includePrices() {
        let w1 = makeWatch(brand: "Rolex", model: "Submariner", price: 12_000_000)
        let w2 = makeWatch(brand: "Tudor", model: "Black Bay", price: 4_500_000)
        addMeasurement(to: w1)
        try? context.save()

        let data = MasterReportGenerator.generate(watches: [w1, w2], includePrices: true)
        assertIsPDF(data)
    }

    func test_masterReport_excludePrices_producesPDF() {
        let w1 = makeWatch()
        try? context.save()

        let data = MasterReportGenerator.generate(watches: [w1], includePrices: false)
        assertIsPDF(data)
    }

    // MARK: - CollectionGalleryGenerator (HTML)

    func test_gallery_html_containsCoreFields() throws {
        let w1 = makeWatch(brand: "Seiko", model: "SPB143", caliber: "6R35")
        try? context.save()

        let url = try XCTUnwrap(
            CollectionGalleryGenerator.generate(watches: [w1], includePrices: false, ownerName: "")
        )
        let html = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"), "must be a self-contained HTML doc")
        XCTAssertTrue(html.contains("Seiko"), "brand should appear")
        XCTAssertTrue(html.contains("SPB143"), "model should appear")
        XCTAssertTrue(html.contains("6R35"), "caliber should appear when set")
        // ownerName 비었으면 기본 제목.
        XCTAssertTrue(html.contains("<title>TickLab Collection</title>"))
        XCTAssertTrue(html.contains("</html>"))

        try? FileManager.default.removeItem(at: url)
    }

    func test_gallery_html_ownerName_inTitle() throws {
        let w1 = makeWatch()
        try? context.save()

        let url = try XCTUnwrap(
            CollectionGalleryGenerator.generate(watches: [w1], ownerName: "MK")
        )
        let html = try String(contentsOf: url, encoding: .utf8)
        // 생성기는 ownerName 을 그대로 보간(HTML escape 없음) → 리터럴 형태 그대로.
        XCTAssertTrue(html.contains("<title>MK's Collection</title>"))
        XCTAssertTrue(html.contains("MK's Collection"))

        try? FileManager.default.removeItem(at: url)
    }

    func test_gallery_html_includePrices_rendersPriceBlock() throws {
        let w1 = makeWatch(brand: "Grand Seiko", model: "Snowflake", price: 7_000_000, currency: "KRW")
        try? context.save()

        let withPrices = try XCTUnwrap(
            CollectionGalleryGenerator.generate(watches: [w1], includePrices: true)
        )
        let htmlWith = try String(contentsOf: withPrices, encoding: .utf8)
        XCTAssertTrue(htmlWith.contains("class=\"price\""),
                      "price block should render when includePrices == true and price set")

        let withoutPrices = try XCTUnwrap(
            CollectionGalleryGenerator.generate(watches: [w1], includePrices: false)
        )
        let htmlWithout = try String(contentsOf: withoutPrices, encoding: .utf8)
        XCTAssertFalse(htmlWithout.contains("class=\"price\""),
                       "price block should be omitted when includePrices == false")

        try? FileManager.default.removeItem(at: withPrices)
        try? FileManager.default.removeItem(at: withoutPrices)
    }

    func test_gallery_html_manualCaliber_omitsCaliberSuffix() throws {
        let w1 = makeWatch(brand: "Custom", model: "DIY", caliber: Watch.manualCaliberTag)
        try? context.save()

        let url = try XCTUnwrap(CollectionGalleryGenerator.generate(watches: [w1]))
        let html = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(html.contains(Watch.manualCaliberTag),
                       "manual sentinel must never leak into output HTML")

        try? FileManager.default.removeItem(at: url)
    }

    func test_gallery_html_watchCount_inHeader() throws {
        let w1 = makeWatch(brand: "A", model: "1")
        let w2 = makeWatch(brand: "B", model: "2")
        try? context.save()

        let url = try XCTUnwrap(CollectionGalleryGenerator.generate(watches: [w1, w2]))
        let html = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(html.contains("2개 시계"), "header should report the watch count")

        try? FileManager.default.removeItem(at: url)
    }

    func test_gallery_html_referralShareURL_present() throws {
        let w1 = makeWatch()
        try? context.save()

        let url = try XCTUnwrap(CollectionGalleryGenerator.generate(watches: [w1]))
        let html = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(html.contains(ReferralService.shareURL.absoluteString),
                      "footer should link to the TickLab referral share URL")

        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - CollectionShareCardGenerator (PNG)

    func test_shareCard_generatesNonNilPNG() throws {
        let w1 = makeWatch(brand: "IWC", model: "Portugieser")
        let w2 = makeWatch(brand: "Omega", model: "Aqua Terra")
        try? context.save()

        let url = try XCTUnwrap(
            CollectionShareCardGenerator.generate(watches: [w1, w2], ownerName: "Collector"),
            "share card image URL should not be nil"
        )
        XCTAssertEqual(url.pathExtension, "png")
        let data = try Data(contentsOf: url)
        XCTAssertFalse(data.isEmpty, "rendered PNG should not be empty")
        // PNG 매직 넘버: 89 50 4E 47
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])

        try? FileManager.default.removeItem(at: url)
    }

    func test_shareCard_emptyOwnerName_stillGenerates() throws {
        let w1 = makeWatch()
        try? context.save()

        let url = try XCTUnwrap(
            CollectionShareCardGenerator.generate(watches: [w1], ownerName: "")
        )
        XCTAssertEqual(url.pathExtension, "png")

        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - WrappedReportData (pure aggregation)

    func test_wrapped_emptyYear_returnsZeros() {
        let data = WrappedReportData.generate(year: 2020, context: context)
        XCTAssertEqual(data.year, 2020)
        XCTAssertEqual(data.totalWears, 0)
        XCTAssertEqual(data.totalMeasurements, 0)
        XCTAssertNil(data.avgRateSecondsPerDay)
        XCTAssertNil(data.mostWornWatch?.watch)
        XCTAssertNil(data.topTag)
        XCTAssertEqual(data.highlightCount, 0)
        XCTAssertEqual(data.newWatchesAdded, 0)
    }

    func test_wrapped_aggregatesWearsMeasurementsAndTags() throws {
        let year = 2023
        let cal = Calendar.current
        let dayA = cal.date(from: DateComponents(year: year, month: 3, day: 10))!
        let dayB = cal.date(from: DateComponents(year: year, month: 6, day: 20))!

        let w1 = makeWatch(brand: "Most", model: "Worn")
        let w2 = makeWatch(brand: "Least", model: "Worn")
        w1.createdAt = dayA   // 신규 시계 카운트 대상

        // w1 두 번, w2 한 번 착용 + 태그 + 하이라이트.
        let l1 = WearLog(watch: w1, date: dayA, tags: ["비즈니스"], isHighlight: true)
        let l2 = WearLog(watch: w1, date: dayB, tags: ["비즈니스", "여행"])
        let l3 = WearLog(watch: w2, date: dayB, tags: ["캐주얼"])
        [l1, l2, l3].forEach { context.insert($0) }

        // 측정 2건 (rate 평균 = (2 + 4)/2 = 3).
        addMeasurement(to: w1, rate: 2.0, timestamp: dayA)
        addMeasurement(to: w2, rate: 4.0, timestamp: dayB)
        try context.save()

        let data = WrappedReportData.generate(year: year, context: context)
        XCTAssertEqual(data.year, year)
        XCTAssertEqual(data.totalWears, 3)
        XCTAssertEqual(data.totalMeasurements, 2)
        XCTAssertEqual(data.avgRateSecondsPerDay ?? 0, 3.0, accuracy: 0.0001)
        XCTAssertEqual(data.mostWornWatch?.count, 2)
        XCTAssertEqual(data.mostWornWatch?.watch.brand, "Most")
        XCTAssertEqual(data.leastWornWatch?.count, 1)
        XCTAssertEqual(data.topTag, "비즈니스", "가장 많이 쓴 태그가 topTag")
        XCTAssertEqual(data.highlightCount, 1)
        XCTAssertEqual(data.newWatchesAdded, 1, "해당 연도 createdAt 시계만 신규 카운트")
    }

    func test_wrapped_excludesOtherYears() throws {
        let cal = Calendar.current
        let w1 = makeWatch()
        let in2022 = cal.date(from: DateComponents(year: 2022, month: 5, day: 1))!
        let in2023 = cal.date(from: DateComponents(year: 2023, month: 5, day: 1))!
        context.insert(WearLog(watch: w1, date: in2022))
        context.insert(WearLog(watch: w1, date: in2023))
        try context.save()

        let data2023 = WrappedReportData.generate(year: 2023, context: context)
        XCTAssertEqual(data2023.totalWears, 1, "2023 로그만 집계되어야 함")
    }
}
