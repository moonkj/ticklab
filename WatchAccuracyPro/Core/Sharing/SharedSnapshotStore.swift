import Foundation

/// 위젯과 메인 앱이 공유하는 가장 최근 측정 스냅샷.
/// App Group `group.com.ticklab.watchaccuracypro` 의 UserDefaults 에 JSON 으로 저장.
struct LatestMeasurementSnapshot: Codable, Equatable, Sendable {
    /// Round 17/24 (Doyoon/Min): app ↔ widget 프로세스 간 schema 변화 감지용.
    /// **호환 규칙 (반드시 준수)**:
    /// 1. 신규 필드는 **반드시 Optional + default** 로 추가 (양방향 decode 호환).
    /// 2. 기존 필드 type 변경 또는 제거 시 schemaVersion bump + 매뉴얼 마이그레이션.
    /// 3. read() 가 currentMaxKnown 초과 version 만나면 nil 반환 → widget placeholder.
    /// 4. 같은 schemaVersion 안에서 Optional 추가는 안전, required 추가는 호환성 깸.
    static let currentSchemaVersion: Int = 1
    var schemaVersion: Int = LatestMeasurementSnapshot.currentSchemaVersion
    var watchName: String
    var caliber: String?
    var timestamp: Date
    var rateSecondsPerDay: Double
    var beatErrorMs: Double
    var amplitudeDegrees: Double?
    var bph: Int
    var confidenceScore: Int

    static let placeholder = LatestMeasurementSnapshot(
        watchName: "TickLab",
        caliber: nil,
        timestamp: Date(),
        rateSecondsPerDay: 0,
        beatErrorMs: 0,
        amplitudeDegrees: nil,
        bph: 28800,
        confidenceScore: 0
    )
}

enum SharedSnapshotStore {
    static let appGroupId = "group.com.ticklab.watchaccuracypro"
    private static let key = "ticklab.latestSnapshot"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    /// Round 17 (Doyoon): JSONEncoder/Decoder 의 date strategy 를 명시 — 양쪽 프로세스가
    ///   같은 형식을 약속하지 않으면 widget decode 가 silently fail 한 채 stale placeholder 노출.
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func write(_ snapshot: LatestMeasurementSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }

    static func read() -> LatestMeasurementSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        guard let decoded = try? decoder.decode(LatestMeasurementSnapshot.self, from: data) else { return nil }
        // Round 24 (Min): 미지 schema 버전 → widget 이 보장된 형식으로만 표시하도록 nil (placeholder fallback).
        //   alien version 데이터를 추정 표시하지 않음.
        guard decoded.schemaVersion <= LatestMeasurementSnapshot.currentSchemaVersion else { return nil }
        return decoded
    }

    static func clear() {
        defaults?.removeObject(forKey: key)
    }
}
