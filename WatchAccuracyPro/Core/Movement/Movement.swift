import Foundation

enum Escapement: String, Codable, Sendable {
    case swissLever
    case coAxial
    case springDrive
    case detentEscapement
}

enum ReliabilityLabel: String, Codable, Sendable {
    case high
    case medium
    case low
}

struct Movement: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let brandFamilies: [String]
    let bph: Int
    let liftAngleDegrees: Double
    let escapement: Escapement
    let typicalAmplitudeMin: Double?
    let typicalAmplitudeMax: Double?
    let coscToleranceMin: Double?
    let coscToleranceMax: Double?
    let confidenceLabel: ReliabilityLabel

    var typicalAmplitudeRange: ClosedRange<Double>? {
        guard let min = typicalAmplitudeMin, let max = typicalAmplitudeMax, min <= max else { return nil }
        return min...max
    }

    var coscToleranceRange: ClosedRange<Double>? {
        guard let min = coscToleranceMin, let max = coscToleranceMax, min <= max else { return nil }
        return min...max
    }

    /// `medium` 또는 `low` 신뢰도 무브먼트는 amplitude를 표시하지 않는다.
    var shouldDisplayAmplitude: Bool {
        confidenceLabel == .high
    }
}
