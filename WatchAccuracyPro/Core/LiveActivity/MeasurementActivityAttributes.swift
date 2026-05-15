import ActivityKit
import Foundation

/// 측정 진행을 Live Activity / Dynamic Island 로 노출하기 위한 attributes.
/// Phase 2 베타: 측정 중 잠금화면에서 진행률 + 임시 BPH/rate 표시.
struct MeasurementActivityAttributes: ActivityAttributes {
    public typealias ContentState = MeasurementContentState

    public struct MeasurementContentState: Codable, Hashable, Sendable {
        var elapsedSeconds: Double
        var bph: Int?
        var rateSecondsPerDay: Double?
        var beatErrorMs: Double?
        var amplitudeDegrees: Double?
        var confidenceScore: Int

        static let placeholder = MeasurementContentState(
            elapsedSeconds: 0,
            bph: nil,
            rateSecondsPerDay: nil,
            beatErrorMs: nil,
            amplitudeDegrees: nil,
            confidenceScore: 0
        )
    }

    var watchName: String
    var caliber: String?
    var startedAt: Date
}
