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
    static func export(watch: Watch, format: ExportFormat, context: ModelContext? = nil) -> ExportPayload {
        export(watches: [watch], format: format, context: context)
    }

    /// 컬렉션 전체를 export. context 제공 시(JSON) 생활기록(착용·일기·정비·스펙카드)까지 포함.
    static func export(watches: [Watch], format: ExportFormat, context: ModelContext? = nil) -> ExportPayload {
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
            let watchIds = Set(watches.map(\.id))
            var dto = WatchesDTO(
                exportedAt: isoFormatter.string(from: Date()),
                watches: watches.map { WatchDTO(from: $0) }
            )
            if let context {
                let wear = ((try? context.fetch(FetchDescriptor<WearLog>())) ?? []).filter { $0.watch.map { watchIds.contains($0.id) } ?? false }
                dto.wearLogs = wear.map(WearLogDTO.init(from:))
                let js = ((try? context.fetch(FetchDescriptor<JournalEntry>())) ?? []).filter { $0.watch.map { watchIds.contains($0.id) } ?? false }
                dto.journals = js.map(JournalDTO.init(from:))
                let svc = ((try? context.fetch(FetchDescriptor<ServiceLog>())) ?? []).filter { $0.watch.map { watchIds.contains($0.id) } ?? false }
                dto.serviceLogs = svc.map(ServiceLogDTO.init(from:))
                let specs = ((try? context.fetch(FetchDescriptor<SpecCard>())) ?? []).filter { $0.watch.map { watchIds.contains($0.id) } ?? false }
                dto.specCards = specs.map(SpecCardDTO.init(from:))
            }
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
        // 생활기록 모델 — 구버전 백업 호환 위해 optional(없으면 nil).
        var wearLogs: [WearLogDTO]? = nil
        var journals: [JournalDTO]? = nil
        var serviceLogs: [ServiceLogDTO]? = nil
        var specCards: [SpecCardDTO]? = nil
    }

    // MARK: - 파일 base64 헬퍼 (사진·사운드·영수증 — 복원 시 새 파일로 기록)
    private static func fileToBase64(_ path: String?) -> String? {
        guard let path, !path.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return data.base64EncodedString()
    }
    private static func base64ToFile(_ base64: String?, ext: String) -> String? {
        guard let base64, let data = Data(base64Encoded: base64) else { return nil }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("restored", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString).\(ext)")
        guard (try? data.write(to: url)) != nil else { return nil }
        return url.path
    }

    // MARK: - 생활기록 DTO (착용·일기·정비·스펙카드) — watch 는 id 로 재링크.
    private struct WearLogDTO: Codable {
        let id: UUID; let watchId: UUID?; let date: Date; let isAuto: Bool
        let note: String; let tags: [String]; let isHighlight: Bool
        init(from w: WearLog) {
            id = w.id; watchId = w.watch?.id; date = w.date; isAuto = w.isAuto
            note = w.note; tags = w.tags; isHighlight = w.isHighlight
        }
        func make(_ byID: [UUID: Watch]) -> WearLog {
            WearLog(id: id, watch: watchId.flatMap { byID[$0] }, date: date,
                    isAuto: isAuto, note: note, tags: tags, isHighlight: isHighlight)
        }
    }

    private struct JournalDTO: Codable {
        let id: UUID; let watchId: UUID?; let measurementId: UUID?; let timestamp: Date
        let body: String; let photosBase64: [String]; let moodRaw: String
        let locationLabel: String?; let peopleRaw: String; let eventRaw: String
        init(from j: JournalEntry) {
            id = j.id; watchId = j.watch?.id; measurementId = j.measurementId; timestamp = j.timestamp
            body = j.body; photosBase64 = j.photoPaths.compactMap { fileToBase64($0) }
            moodRaw = j.moodRaw; locationLabel = j.locationLabel
            peopleRaw = j.peopleRaw; eventRaw = j.eventRaw
        }
        func make(_ byID: [UUID: Watch]) -> JournalEntry {
            let paths = photosBase64.compactMap { base64ToFile($0, ext: "jpg") }
            let j = JournalEntry(id: id, watch: watchId.flatMap { byID[$0] }, measurementId: measurementId,
                                 timestamp: timestamp, body: body, photoPaths: paths,
                                 mood: Mood(rawValue: moodRaw) ?? .neutral, locationLabel: locationLabel)
            j.peopleRaw = peopleRaw; j.eventRaw = eventRaw
            return j
        }
    }

    private struct ServiceLogDTO: Codable {
        let id: UUID; let watchId: UUID?; let timestamp: Date; let typeRaw: String
        let serviceCenter: String; let costAmount: Decimal?; let costCurrency: String?
        let notes: String; let nextServiceDate: Date?; let receiptBase64: String?
        init(from s: ServiceLog) {
            id = s.id; watchId = s.watch?.id; timestamp = s.timestamp; typeRaw = s.typeRaw
            serviceCenter = s.serviceCenter; costAmount = s.costAmount; costCurrency = s.costCurrency
            notes = s.notes; nextServiceDate = s.nextServiceDate; receiptBase64 = fileToBase64(s.receiptPath)
        }
        func make(_ byID: [UUID: Watch]) -> ServiceLog {
            ServiceLog(id: id, watch: watchId.flatMap { byID[$0] }, timestamp: timestamp,
                       type: ServiceType(rawValue: typeRaw) ?? .checkup,
                       serviceCenter: serviceCenter, costAmount: costAmount, costCurrency: costCurrency,
                       notes: notes, nextServiceDate: nextServiceDate,
                       receiptPath: base64ToFile(receiptBase64, ext: "jpg"))
        }
    }

    private struct SpecCardDTO: Codable {
        let id: UUID; let watchId: UUID?; let createdAt: Date; let title: String; let movement: String
        let caseSize: Double?; let liftAngle: Double?; let powerReserveHours: Double?
        let photoBase64: String?; let audioBase64: String?; let note: String
        let aiDescription: String?; let caseThickness: Double?; let lugToLug: Double?
        let waterResistanceM: Int?; let crystal: String?; let dialColor: String?; let caseMaterial: String?
        init(from c: SpecCard) {
            id = c.id; watchId = c.watch?.id; createdAt = c.createdAt; title = c.title; movement = c.movement
            caseSize = c.caseSize; liftAngle = c.liftAngle; powerReserveHours = c.powerReserveHours
            photoBase64 = fileToBase64(c.photoPath); audioBase64 = fileToBase64(c.audioPath); note = c.note
            aiDescription = c.aiDescription; caseThickness = c.caseThickness; lugToLug = c.lugToLug
            waterResistanceM = c.waterResistanceM; crystal = c.crystal; dialColor = c.dialColor; caseMaterial = c.caseMaterial
        }
        func make(_ byID: [UUID: Watch]) -> SpecCard {
            let c = SpecCard(id: id, watch: watchId.flatMap { byID[$0] }, createdAt: createdAt,
                             title: title, movement: movement, caseSize: caseSize, liftAngle: liftAngle,
                             powerReserveHours: powerReserveHours,
                             photoPath: base64ToFile(photoBase64, ext: "jpg"),
                             audioPath: base64ToFile(audioBase64, ext: "m4a"), note: note)
            c.aiDescription = aiDescription; c.caseThickness = caseThickness; c.lugToLug = lugToLug
            c.waterResistanceM = waterResistanceM; c.crystal = crystal; c.dialColor = dialColor; c.caseMaterial = caseMaterial
            return c
        }
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
        // 스마트워치 배터리(완충 지속일·마지막 완충 시각) + 무브먼트 확정 여부 — 구버전 백업 호환 위해 optional.
        let batteryFullChargeDays: Double?
        let batteryChargedAt: Date?
        let movementConfirmed: Bool?
        let purchaseConditionRaw: String?
        let productionYear: Int?
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
            batteryFullChargeDays = w.batteryFullChargeDays
            batteryChargedAt = w.batteryChargedAt
            movementConfirmed = w.movementConfirmed
            purchaseConditionRaw = w.purchaseConditionRaw
            productionYear = w.productionYear
            photoBase64 = w.photoData?.base64EncodedString()
            createdAt = w.createdAt
            measurements = w.measurements.sorted(by: { $0.timestamp < $1.timestamp }).map(MeasurementDTO.init(from:))
        }

        func makeWatch() -> Watch {
            let w = Watch(
                id: id, brand: brand, model: model, caliber: caliber,
                purchaseDate: purchaseDate,
                photoData: photoBase64.flatMap { Data(base64Encoded: $0) },
                serviceHistory: serviceHistory, isPrimary: isPrimary,
                liftAngleOverride: liftAngleOverride,
                movementType: WatchMovementType(rawValue: movementTypeRaw) ?? .automatic,
                movementConfirmed: movementConfirmed ?? true,
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
            // 스마트워치 배터리 — Watch init 파라미터에 없어 후속 set(완충 지속일·마지막 완충 시각 복원).
            w.batteryFullChargeDays = batteryFullChargeDays
            w.batteryChargedAt = batteryChargedAt
            w.purchaseConditionRaw = purchaseConditionRaw
            w.productionYear = productionYear
            return w
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
        let notes: String?
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
            self.notes = m.notes
            self.metadata = m.metadata
        }

        func makeMeasurement() -> WatchMeasurement {
            let m = WatchMeasurement(
                id: id, timestamp: timestamp, rateSecondsPerDay: rateSecondsPerDay,
                beatErrorMs: beatErrorMs, amplitudeDegrees: amplitudeDegrees, bph: bph,
                confidenceScore: confidenceScore, durationSeconds: durationSeconds, metadata: metadata
            )
            m.notes = notes
            return m
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
        // 생활기록 복원 — watch 를 id 로 재링크(이미 있던 시계 포함). 중복 id 는 건너뜀. 파일은 새로 기록.
        let byID = Dictionary(((try? context.fetch(FetchDescriptor<Watch>())) ?? []).map { ($0.id, $0) },
                              uniquingKeysWith: { a, _ in a })
        let exWear = Set(((try? context.fetch(FetchDescriptor<WearLog>())) ?? []).map(\.id))
        for d in (dto.wearLogs ?? []) where !exWear.contains(d.id) { context.insert(d.make(byID)) }
        let exJournal = Set(((try? context.fetch(FetchDescriptor<JournalEntry>())) ?? []).map(\.id))
        for d in (dto.journals ?? []) where !exJournal.contains(d.id) { context.insert(d.make(byID)) }
        let exService = Set(((try? context.fetch(FetchDescriptor<ServiceLog>())) ?? []).map(\.id))
        for d in (dto.serviceLogs ?? []) where !exService.contains(d.id) { context.insert(d.make(byID)) }
        let exSpec = Set(((try? context.fetch(FetchDescriptor<SpecCard>())) ?? []).map(\.id))
        for d in (dto.specCards ?? []) where !exSpec.contains(d.id) { context.insert(d.make(byID)) }
        let lifeCount = (dto.wearLogs?.count ?? 0) + (dto.journals?.count ?? 0)
            + (dto.serviceLogs?.count ?? 0) + (dto.specCards?.count ?? 0)
        // 대표 시계(isPrimary) 단일 불변식 강제 — 가져온 백업이 이미 있는 대표와 겹쳐 2개가 되는 것 방지.
        let allWatches = (try? context.fetch(FetchDescriptor<Watch>())) ?? []
        let primaries = allWatches.filter { $0.isPrimary }
        if primaries.count > 1 {
            // 가장 먼저 만들어진 시계 1개만 대표 유지, 나머지 해제.
            let keep = primaries.min(by: { $0.createdAt < $1.createdAt })
            for w in primaries where w.id != keep?.id { w.isPrimary = false }
        }
        if imported > 0 || lifeCount > 0 || primaries.count > 1 { try? context.save() }
        return imported
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

}
