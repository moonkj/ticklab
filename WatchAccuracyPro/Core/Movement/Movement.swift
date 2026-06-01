import Foundation

enum Escapement: String, Codable, Sendable {
    case swissLever
    case coAxial
    case springDrive
    case detentEscapement
    /// Round 88: Ulysse Nardin DIAMonSIL 등 실리콘 이스케이프먼트 (동작은 swiss lever 유사).
    case siliconEscapement
    /// Round 88: HFQ 쿼츠 (Bulova Precisionist 등). DSP 측정 부적합 → confidence low.
    case quartz
}

enum ReliabilityLabel: String, Codable, Sendable {
    case veryHigh    // T-08: COSC 인증 등 실기기 검증 완료 — 최상 신뢰
    case high
    case medium
    case low
    case unverified  // T-08: 커뮤니티 제보·미검증 — amplitude 비표시(Hard Rule 9)

    /// amplitude 표시 가능 등급 — high/veryHigh 만. medium·low·unverified 는 비표시.
    var displaysAmplitude: Bool { self == .high || self == .veryHigh }
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

    /// high/veryHigh 외(medium·low·unverified) 신뢰도 무브먼트는 amplitude를 표시하지 않는다.
    var shouldDisplayAmplitude: Bool {
        confidenceLabel.displaysAmplitude
    }
}
