import AVFoundation
import Foundation

/// 디바이스에서 사용 가능한 오디오 입력을 열거하고, 사용자가 선택한 입력을 추적한다.
/// `MicrophoneType` 은 `MeasurementMetadata.microphoneType` 으로 그대로 매핑된다.
@Observable
final class AudioInputManager {
    static let shared = AudioInputManager()

    struct Input: Identifiable, Hashable {
        let id: String          // portUID
        let displayName: String
        let portType: AVAudioSession.Port
        let microphoneType: MicrophoneType
    }

    private(set) var available: [Input] = []
    private(set) var preferredInputUID: String?

    private enum DefaultsKey {
        static let preferred = "ticklab.audio.preferredInputUID"
    }

    init() {
        self.preferredInputUID = UserDefaults.standard.string(forKey: DefaultsKey.preferred)
        refresh()
        NotificationCenter.default.addObserver(
            self, selector: #selector(routeChanged(_:)),
            name: AVAudioSession.routeChangeNotification, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func routeChanged(_ note: Notification) {
        Task { @MainActor in self.refresh() }
    }

    func refresh() {
        let session = AVAudioSession.sharedInstance()
        let inputs = session.availableInputs ?? []
        self.available = inputs.map { port in
            Input(
                id: port.uid,
                displayName: port.portName,
                portType: port.portType,
                microphoneType: AudioInputManager.classify(port: port)
            )
        }
    }

    func setPreferred(_ input: Input?) {
        preferredInputUID = input?.id
        if let id = input?.id {
            UserDefaults.standard.set(id, forKey: DefaultsKey.preferred)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.preferred)
        }
    }

    /// 현재 활성 input 찾아서 AVAudioSession 에 적용. 호출 직후 `setActive(true)` 필요.
    func applyPreferredToSession() throws {
        let session = AVAudioSession.sharedInstance()
        guard let preferredUID = preferredInputUID,
              let target = (session.availableInputs ?? []).first(where: { $0.uid == preferredUID }) else {
            return
        }
        try session.setPreferredInput(target)
    }

    /// 현재 활성 입력의 마이크 타입.
    var activeMicrophoneType: MicrophoneType {
        let session = AVAudioSession.sharedInstance()
        guard let port = session.currentRoute.inputs.first else {
            return .builtin
        }
        return AudioInputManager.classify(port: port)
    }

    private static func classify(port: AVAudioSessionPortDescription) -> MicrophoneType {
        classify(portType: port.portType)
    }

    /// 단위 테스트 가능하도록 portType 만 받아 분류. UI/실 디바이스 의존성 없음.
    static func classify(portType: AVAudioSession.Port) -> MicrophoneType {
        switch portType {
        case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE: return .bluetooth
        case .headsetMic, .lineIn:                         return .wired
        case .usbAudio:                                    return .external
        case .builtInMic:                                  return .builtin
        default:                                           return .external
        }
    }
}
