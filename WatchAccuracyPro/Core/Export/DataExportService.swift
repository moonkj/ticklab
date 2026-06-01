import Foundation
import SwiftData

/// 워치메이커 페르소나(김재철)의 핵심 요청 — Excel/Numbers 에서 트렌드 분석할 수 있도록 export.
enum ExportFormat: String, CaseIterable, Identifiable {
    case csv
    case json
    var id: String { rawValue }
    var fileExtension: String { rawValue }
    var mimeType: String {
        switch self {
        case .csv:  return "text/csv"
        case .json: return "application/json"
        }
    }
}

struct ExportPayload: Sendable {
    let filename: String
    let data: Data
    let mimeType: String

    /// ShareLink 가 file URL 을 선호하므로 임시 디렉토리에 한 번 쓰고 URL 반환.
    /// Round 16 (Min): SettingsView 에 잘못 위치하던 extension 을 owner 옆으로 이동.
    var tempURL: URL? {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: tmp, options: .atomic)
            return tmp
        } catch {
            return nil
        }
    }
}

enum DataExportService {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// 한 시계의 모든 측정을 export. 정렬은 timestamp asc.
    static func export(watch: Watch, format: ExportFormat) -> ExportPayload {
        export(watches: [watch], format: format)
    }

    /// 컬렉션 전체를 export.
    static func export(watches: [Watch], format: ExportFormat) -> ExportPayload {
        let stem = "ticklab_export_\(Self.dateStamp())"
        let filename = "\(stem).\(format.fileExtension)"
        switch format {
        case .csv:
            var lines = [csvHeader()]
            for watch in watches {
                let sorted = watch.measurements.sorted(by: { $0.timestamp < $1.timestamp })
                // 헤비 컬렉터 리뷰(#8): 측정 0회 시계도 인벤토리 행으로 포함 — 보유 목록 전체 export.
                if sorted.isEmpty {
                    lines.append(csvRow(watch: watch, measurement: nil))
                } else {
                    for m in sorted {
                        lines.append(csvRow(watch: watch, measurement: m))
                    }
                }
            }
            let body = lines.joined(separator: "\r\n")
            return ExportPayload(filename: filename, data: Data(body.utf8), mimeType: format.mimeType)
        case .json:
            let dto = WatchesDTO(
                exportedAt: isoFormatter.string(from: Date()),
                watches: watches.map { WatchDTO(from: $0) }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = (try? encoder.encode(dto)) ?? Data()
            return ExportPayload(filename: filename, data: data, mimeType: format.mimeType)
        }
    }

    // MARK: - CSV

    private static func csvHeader() -> String {
        // Round 115 (데이터 무결성 Med-3): Round 83 신규 필드 추가.
        // Sprint 13 (F4): 라벨-값 불일치 수정 — 기존 snr_db가 실제로 ambient_noise였음.
        //   진짜 SNR(metadata.snrDB) + 온도 + 파워리저브 추가.
        [
            "timestamp", "brand", "model", "nickname", "reference_number", "caliber",
            "rate_s_per_day", "beat_error_ms", "amplitude_deg",
            "bph", "confidence", "duration_s",
            "ambient_noise_db", "snr_db", "temperature_c", "power_reserve_est_h",
            "position", "microphone", "device"
        ].joined(separator: ",")
    }

    /// measurement 이 nil 이면(측정 0회 시계) 측정 파생 셀은 공란 — 인벤토리 행.
    private static func csvRow(watch: Watch, measurement m: WatchMeasurement?) -> String {
        let metadata = m?.metadata
        // 타입체커 부담 완화 — 셀을 단계적으로 구성.
        var cells: [String] = []
        cells.append(m.map { isoFormatter.string(from: $0.timestamp) } ?? "")
        cells.append(watch.brand)
        cells.append(watch.model)
        cells.append(watch.nickname ?? "")
        cells.append(watch.referenceNumber ?? "")
        cells.append(watch.caliber ?? "")
        cells.append(m.map { String(format: "%.2f", $0.rateSecondsPerDay) } ?? "")
        cells.append(m.map { String(format: "%.2f", $0.beatErrorMs) } ?? "")
        cells.append(m?.amplitudeDegrees.map { String(format: "%.0f", $0) } ?? "")
        cells.append(m.map { String($0.bph) } ?? "")
        cells.append(m.map { String($0.confidenceScore) } ?? "")
        cells.append(m.map { String($0.durationSeconds) } ?? "")
        cells.append(metadata.map { String(format: "%.1f", $0.ambientNoiseDB) } ?? "")
        cells.append(metadata?.snrDB.map { String(format: "%.1f", $0) } ?? "")
        cells.append(metadata?.temperatureCelsius.map { String(format: "%.1f", $0) } ?? "")
        cells.append(metadata?.powerReserveEstimate.map { String(format: "%.1f", $0) } ?? "")
        cells.append(metadata?.position.rawValue ?? "")
        cells.append(metadata?.microphoneType.rawValue ?? "")
        cells.append(metadata?.deviceModel ?? "")
        return cells.map(escapeCSV).joined(separator: ",")
    }

    private static func escapeCSV(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return s
    }

    // MARK: - JSON DTO

    private struct WatchesDTO: Codable {
        let exportedAt: String
        let watches: [WatchDTO]
    }

    /// #10 백업/복원: full round-trip — 모든 Watch 스칼라 필드 + 사진(base64) + 측정 history.
    private struct WatchDTO: Codable {
        let id: UUID
        let brand: String
        let model: String
        let caliber: String?
        let movementTypeRaw: String
        let purchaseDate: Date?
        let serviceHistory: [Date]
        let isPrimary: Bool
        let sortOrder: Double?
        let nickname: String?
        let story: String?
        let referenceNumber: String?
        let purchaseLocation: String?
        let purchaseSalesperson: String?
        let purchasePrice: Decimal?
        let purchaseCurrency: String?
        let warrantyMonths: Int?
        let warrantyReminderEnabled: Bool
        let receivedFrom: String?
        let liftAngleOverride: Double?
        let customBph: Int?
        let windReminderEnabled: Bool
        let windReminderHour: Int
        let windReminderMinute: Int
        let batteryLastReplaced: Date?
        let batteryExpectedLifeMonths: Int
        let batteryReminderEnabled: Bool
        let photoBase64: String?
        let createdAt: Date
        let measurements: [MeasurementDTO]

        init(from w: Watch) {
            id = w.id; brand = w.brand; model = w.model; caliber = w.caliber
            movementTypeRaw = w.movementTypeRaw
            purchaseDate = w.purchaseDate; serviceHistory = w.serviceHistory
            isPrimary = w.isPrimary; sortOrder = w.sortOrder
            nickname = w.nickname; story = w.story; referenceNumber = w.referenceNumber
            purchaseLocation = w.purchaseLocation; purchaseSalesperson = w.purchaseSalesperson
            purchasePrice = w.purchasePrice; purchaseCurrency = w.purchaseCurrency
            warrantyMonths = w.warrantyMonths; warrantyReminderEnabled = w.warrantyReminderEnabled
            receivedFrom = w.receivedFrom; liftAngleOverride = w.liftAngleOverride; customBph = w.customBph
            windReminderEnabled = w.windReminderEnabled; windReminderHour = w.windReminderHour
            windReminderMinute = w.windReminderMinute
            batteryLastReplaced = w.batteryLastReplaced; batteryExpectedLifeMonths = w.batteryExpectedLifeMonths
            batteryReminderEnabled = w.batteryReminderEnabled
            photoBase64 = w.photoData?.base64EncodedString()
            createdAt = w.createdAt
            measurements = w.measurements.sorted(by: { $0.timestamp < $1.timestamp }).map(MeasurementDTO.init(from:))
        }

        func makeWatch() -> Watch {
            Watch(
                id: id, brand: brand, model: model, caliber: caliber,
                purchaseDate: purchaseDate,
                photoData: photoBase64.flatMap { Data(base64Encoded: $0) },
                serviceHistory: serviceHistory, isPrimary: isPrimary,
                liftAngleOverride: liftAngleOverride,
                movementType: WatchMovementType(rawValue: movementTypeRaw) ?? .automatic,
                nickname: nickname, story: story, referenceNumber: referenceNumber,
                sortOrder: sortOrder, customBph: customBph,
                windReminderEnabled: windReminderEnabled, windReminderHour: windReminderHour,
                windReminderMinute: windReminderMinute,
                batteryLastReplaced: batteryLastReplaced,
                batteryExpectedLifeMonths: batteryExpectedLifeMonths,
                batteryReminderEnabled: batteryReminderEnabled,
                purchaseLocation: purchaseLocation, purchaseSalesperson: purchaseSalesperson,
                purchasePrice: purchasePrice, purchaseCurrency: purchaseCurrency,
                warrantyMonths: warrantyMonths, warrantyReminderEnabled: warrantyReminderEnabled,
                receivedFrom: receivedFrom, createdAt: createdAt
            )
        }
    }

    private struct MeasurementDTO: Codable {
        let id: UUID
        let timestamp: Date
        let rateSecondsPerDay: Double
        let beatErrorMs: Double
        let amplitudeDegrees: Double?
        let bph: Int
        let confidenceScore: Int
        let durationSeconds: Int
        let metadata: MeasurementMetadata

        init(from m: WatchMeasurement) {
            self.id = m.id
            self.timestamp = m.timestamp
            self.rateSecondsPerDay = m.rateSecondsPerDay
            self.beatErrorMs = m.beatErrorMs
            self.amplitudeDegrees = m.amplitudeDegrees
            self.bph = m.bph
            self.confidenceScore = m.confidenceScore
            self.durationSeconds = m.durationSeconds
            self.metadata = m.metadata
        }

        func makeMeasurement() -> WatchMeasurement {
            WatchMeasurement(
                id: id, timestamp: timestamp, rateSecondsPerDay: rateSecondsPerDay,
                beatErrorMs: beatErrorMs, amplitudeDegrees: amplitudeDegrees, bph: bph,
                confidenceScore: confidenceScore, durationSeconds: durationSeconds, metadata: metadata
            )
        }
    }

    // MARK: - Import (복원) — 로컬 JSON 파일에서. 외부 전송 0 (Hard Rule #8 무충돌).

    /// 백업 JSON 을 가져와 복원. 이미 존재하는 id 는 건너뜀(중복 방지). 가져온 시계 수 반환.
    @MainActor
    static func importWatches(from data: Data, into context: ModelContext) -> Int {
        guard let dto = try? JSONDecoder().decode(WatchesDTO.self, from: data) else { return 0 }
        let existing = Set(((try? context.fetch(FetchDescriptor<Watch>())) ?? []).map(\.id))
        var imported = 0
        for wdto in dto.watches where !existing.contains(wdto.id) {
            let watch = wdto.makeWatch()
            context.insert(watch)
            for mdto in wdto.measurements {
                let m = mdto.makeMeasurement()
                m.watch = watch
                context.insert(m)
            }
            imported += 1
        }
        if imported > 0 { try? context.save() }
        return imported
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

}
