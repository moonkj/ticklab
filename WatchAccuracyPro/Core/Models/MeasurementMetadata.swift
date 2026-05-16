import Foundation

enum MicrophoneType: String, Codable, Sendable {
    case builtin
    case wired
    case bluetooth
    case external

    var localizationKey: String {
        switch self {
        case .builtin:   return "audio.input.builtin"
        case .wired:     return "audio.input.wired"
        case .bluetooth: return "audio.input.bluetooth"
        case .external:  return "audio.input.external"
        }
    }
}

struct MeasurementMetadata: Codable, Sendable, Equatable {
    var position: Position
    var temperatureCelsius: Double?
    /// Round 18 (Doyoon): 이전 build 가 SNR 을 이 필드에 잘못 저장한 history. 이름 자체는 보존
    ///   (마이그레이션 회피) 하되 신규 데이터는 snrDB 사용.
    var ambientNoiseDB: Double
    /// Round 18: 신규 — 측정 시점 SNR(dB). nil 이면 legacy build 데이터.
    var snrDB: Double?
    var powerReserveEstimate: Double?
    var deviceModel: String
    var microphoneType: MicrophoneType
    /// Round 95: 측정 시작 시 NTP offset (ms). 디바이스 시계 - 서버 시계 차이.
    /// 측정값 자체는 audio sample rate 기반이라 영향 없지만, 추후 trend 분석 시 신뢰도 보강.
    var ntpOffsetMs: Double?

    init(
        position: Position = .unknown,
        temperatureCelsius: Double? = nil,
        ambientNoiseDB: Double = 0,
        snrDB: Double? = nil,
        powerReserveEstimate: Double? = nil,
        deviceModel: String = "",
        microphoneType: MicrophoneType = .builtin,
        ntpOffsetMs: Double? = nil
    ) {
        self.position = position
        self.temperatureCelsius = temperatureCelsius
        self.ambientNoiseDB = ambientNoiseDB
        self.snrDB = snrDB
        self.powerReserveEstimate = powerReserveEstimate
        self.deviceModel = deviceModel
        self.microphoneType = microphoneType
        self.ntpOffsetMs = ntpOffsetMs
    }
}
