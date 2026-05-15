import Foundation

/// 위젯과 메인 앱이 공유하는 가장 최근 측정 스냅샷.
/// App Group `group.com.ticklab.watchaccuracypro` 의 UserDefaults 에 JSON 으로 저장.
struct LatestMeasurementSnapshot: Codable, Equatable, Sendable {
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

    static func write(_ snapshot: LatestMeasurementSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }

    static func read() -> LatestMeasurementSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LatestMeasurementSnapshot.self, from: data)
    }

    static func clear() {
        defaults?.removeObject(forKey: key)
    }
}
