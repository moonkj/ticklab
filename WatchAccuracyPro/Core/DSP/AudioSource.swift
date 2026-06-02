import Foundation

/// 오디오 샘플 스트림의 추상화. 실 디바이스 마이크(`AudioCapture`) 와
/// 합성 신호(`SyntheticAudioSource`, 테스트용) 모두 이 프로토콜을 구현해
/// DSPPipeline 이 양쪽에 동일하게 동작한다.
protocol AudioSource: AnyObject {
    var sampleRate: Double { get }

    /// Round 172: 오디오 클록 vs 시스템(host=mach) 클록 드리프트 보정 계수. true_period = measured × factor.
    /// iPhone 오디오 클록이 48000Hz 가정과 ~±수십 ppm 어긋나면 rate 에 고정 bias(예: −80ppm→−7 s/d).
    /// AudioCapture 가 AVAudioTime(정밀 하드웨어 타임스탬프 `hostTime`/`sampleTime`)으로 산출 — 콜백 지터 무관.
    /// 단기적으로 안정적인 mach 기준 상대보정. 절대 오차(mach↔진짜)는 ClockCalibrationService(NTP 누적)가 보정.
    /// 합성/테스트는 1.0(보정 없음).
    var clockDriftFactor: Double { get }

    /// 캡처/생성을 시작한다. 호출 후 `onBuffer` 가 청크 단위로 호출된다.
    func start(onBuffer: @escaping ([Float]) -> Void) throws

    /// 캡처/생성을 멈춘다. 호출 후 `onBuffer` 는 더 이상 호출되지 않는다.
    func stop()
}

extension AudioSource {
    /// 기본 — 보정 없음(합성 소스/테스트). AudioCapture 가 override.
    var clockDriftFactor: Double { 1.0 }
}

enum AudioSourceError: Error {
    case permissionDenied
    case sessionConfigurationFailed(underlying: Error)
    case engineStartFailed(underlying: Error)
}
