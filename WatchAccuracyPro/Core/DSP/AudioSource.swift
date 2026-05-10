import Foundation

/// 오디오 샘플 스트림의 추상화. 실 디바이스 마이크(`AudioCapture`) 와
/// 합성 신호(`SyntheticAudioSource`, 테스트용) 모두 이 프로토콜을 구현해
/// DSPPipeline 이 양쪽에 동일하게 동작한다.
protocol AudioSource: AnyObject {
    var sampleRate: Double { get }

    /// 캡처/생성을 시작한다. 호출 후 `onBuffer` 가 청크 단위로 호출된다.
    func start(onBuffer: @escaping ([Float]) -> Void) throws

    /// 캡처/생성을 멈춘다. 호출 후 `onBuffer` 는 더 이상 호출되지 않는다.
    func stop()
}

enum AudioSourceError: Error {
    case permissionDenied
    case sessionConfigurationFailed(underlying: Error)
    case engineStartFailed(underlying: Error)
}
