import Foundation

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
                for m in sorted {
                    lines.append(csvRow(watch: watch, measurement: m))
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

    private static func makeCSV(watch: Watch, measurements: [WatchMeasurement]) -> Data {
        var lines = [csvHeader()]
        for m in measurements {
            lines.append(csvRow(watch: watch, measurement: m))
        }
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    private static func csvHeader() -> String {
        // Round 115 (데이터 무결성 Med-3): Round 83 신규 필드 추가.
        [
            "timestamp", "brand", "model", "nickname", "reference_number", "caliber",
            "rate_s_per_day", "beat_error_ms", "amplitude_deg",
            "bph", "confidence", "duration_s", "snr_db",
            "position", "microphone", "device"
        ].joined(separator: ",")
    }

    private static func csvRow(watch: Watch, measurement m: WatchMeasurement) -> String {
        let metadata = m.metadata
        let cells: [String] = [
            isoFormatter.string(from: m.timestamp),
            watch.brand,
            watch.model,
            watch.nickname ?? "",
            watch.referenceNumber ?? "",
            watch.caliber ?? "",
            String(format: "%.2f", m.rateSecondsPerDay),
            String(format: "%.2f", m.beatErrorMs),
            m.amplitudeDegrees.map { String(format: "%.0f", $0) } ?? "",
            String(m.bph),
            String(m.confidenceScore),
            String(m.durationSeconds),
            String(format: "%.1f", metadata.ambientNoiseDB),
            metadata.position.rawValue,
            metadata.microphoneType.rawValue,
            metadata.deviceModel
        ].map(escapeCSV)
        return cells.joined(separator: ",")
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

    private struct WatchDTO: Codable {
        let id: UUID
        let brand: String
        let model: String
        let caliber: String?
        let createdAt: Date
        let measurements: [MeasurementDTO]

        init(from watch: Watch) {
            self.id = watch.id
            self.brand = watch.brand
            self.model = watch.model
            self.caliber = watch.caliber
            self.createdAt = watch.createdAt
            self.measurements = watch.measurements
                .sorted(by: { $0.timestamp < $1.timestamp })
                .map(MeasurementDTO.init(from:))
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
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private static func sanitize(filename: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return String(filename.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }
}
