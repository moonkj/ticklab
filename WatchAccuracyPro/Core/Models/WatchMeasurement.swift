import Foundation
import SwiftData

/// 한 번의 시계 정확도 측정 결과.
///
/// 이름이 `WatchMeasurement` 인 이유: Foundation의 제네릭 `Measurement<UnitType>` 와
/// 이름이 충돌해 테스트에서 `Measurement(...)` 호출 시 ambiguous lookup 이 발생한다.
@Model
final class WatchMeasurement {
    @Attribute(.unique) var id: UUID
    var watch: Watch?
    var timestamp: Date
    var rateSecondsPerDay: Double
    var beatErrorMs: Double
    var amplitudeDegrees: Double?
    var bph: Int
    var confidenceScore: Int
    var durationSeconds: Int
    var notes: String?

    private var metadataData: Data
    var metadata: MeasurementMetadata {
        get {
            (try? JSONDecoder().decode(MeasurementMetadata.self, from: metadataData))
                ?? MeasurementMetadata()
        }
        set {
            metadataData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    init(
        id: UUID = UUID(),
        watch: Watch? = nil,
        timestamp: Date = .init(),
        rateSecondsPerDay: Double,
        beatErrorMs: Double,
        amplitudeDegrees: Double? = nil,
        bph: Int,
        confidenceScore: Int,
        durationSeconds: Int,
        metadata: MeasurementMetadata = MeasurementMetadata(),
        notes: String? = nil
    ) {
        self.id = id
        self.watch = watch
        self.timestamp = timestamp
        self.rateSecondsPerDay = rateSecondsPerDay
        self.beatErrorMs = beatErrorMs
        self.amplitudeDegrees = amplitudeDegrees
        self.bph = bph
        self.confidenceScore = confidenceScore
        self.durationSeconds = durationSeconds
        self.metadataData = (try? JSONEncoder().encode(metadata)) ?? Data()
        self.notes = notes
    }
}
