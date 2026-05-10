import Foundation

enum MicrophoneType: String, Codable, Sendable {
    case builtin
    case wired
    case bluetooth
}

struct MeasurementMetadata: Codable, Sendable, Equatable {
    var position: Position
    var temperatureCelsius: Double?
    var ambientNoiseDB: Double
    var powerReserveEstimate: Double?
    var deviceModel: String
    var microphoneType: MicrophoneType

    init(
        position: Position = .unknown,
        temperatureCelsius: Double? = nil,
        ambientNoiseDB: Double = 0,
        powerReserveEstimate: Double? = nil,
        deviceModel: String = "",
        microphoneType: MicrophoneType = .builtin
    ) {
        self.position = position
        self.temperatureCelsius = temperatureCelsius
        self.ambientNoiseDB = ambientNoiseDB
        self.powerReserveEstimate = powerReserveEstimate
        self.deviceModel = deviceModel
        self.microphoneType = microphoneType
    }
}
