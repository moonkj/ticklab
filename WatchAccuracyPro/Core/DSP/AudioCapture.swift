import AVFoundation
import Foundation

/// 디바이스 마이크에서 오디오를 캡처해 100ms 청크 단위로 콜백한다.
/// AVAudioSession은 `.measurement` 카테고리로 설정해 이득 자동조절을 최소화한다.
///
/// 사용자 보고된 "약 신호 미감지" 수정: software gain.
/// .measurement 모드는 AGC off 라 raw 신호가 매우 약하다. 4× 게인 적용해 후속 필터/분석이
/// 동작 가능한 레벨로. 클리핑 가능성이 있어 max 1.0 으로 clamp.
final class AudioCapture: AudioSource {
    let sampleRate: Double = 48_000

    /// .measurement 모드 raw 신호 레벨 보강.
    /// 8× → 4× (audit 권고): voice processing OFF 가 진짜 raw 를 주므로 8× 는 강한 tic clip 유발.
    /// 4× = +12dB. 강한 tic (raw 0.2) 을 0.8 로 → clip 없음.
    // Round 129f: gain 6 → 3. clipping spike 방지가 우선. spike 1번이면 onset detector 후속 모두 noise 판단.
    // Round 132d (사용자: 감지 자체 안됨, 같은 조건 +11.7 성공 vs 완전 실패 반복):
    // 신호가 검출 임계 직전 → 약한 신호 증폭. soft-knee tanh 가 clip 방지하므로 gain 5.0 안전.
    // Round 158 (Lim/Hyemi 패널): -47 dBFS 환경 (IWC sapphire-back) 검출 부족 → 5 → 10 으로 상향.
    // tanh argument 0.9 → 0.6 으로 압축 시작점 늦춰 약신호 헤드룸 확보.
    static let softwareGain: Float = 10.0
    static let tanhArgScale: Float = 0.6

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var onBuffer: (([Float]) -> Void)?
    private let chunkFrames: AVAudioFrameCount = 4_800 // 100ms @ 48kHz
    /// Round 141 (Min H2): 통화/Siri/알람 interruption 핸들러 — engine stale 방지.
    private var interruptionObserver: NSObjectProtocol?

    func start(onBuffer: @escaping ([Float]) -> Void) throws {
        try configureSession()
        self.onBuffer = onBuffer

        let input = engine.inputNode
        // **CRITICAL** (audit 발견): iOS 17+ 에서 voice processing 이 .measurement 모드에서도
        // 자동 OFF 되지 않음. ON 이면 watch tic 의 4kHz+ 대역을 noise suppression 으로 적극 제거.
        // 명시적으로 disable.
        do {
            try input.setVoiceProcessingEnabled(false)
        } catch {
            print("⚠️ setVoiceProcessingEnabled(false) failed: \(error) — DSP 결과에 영향 가능")
        }
        let inputFormat = input.outputFormat(forBus: 0)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioSourceError.sessionConfigurationFailed(
                underlying: NSError(domain: "AudioCapture", code: -1)
            )
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: chunkFrames, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.converter else { return }
            guard let outBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * self.sampleRate / inputFormat.sampleRate)
            ) else { return }
            var error: NSError?
            converter.convert(to: outBuffer, error: &error) { _, status in
                status.pointee = .haveData
                return buffer
            }
            if error != nil { return }
            guard let channel = outBuffer.floatChannelData?[0] else { return }
            let count = Int(outBuffer.frameLength)
            // Round 130 (Dr. Sarah Chen P1): hard clip → soft-knee tanh compression.
            // 환경 spike(손동작, 케이스 마찰)가 1.0 saturate → p95 dominance 망가뜨려 onset 다 놓침.
            // tanh 압축으로 spike도 dynamic range 보존, 후속 정상 tic 살림.
            let gain = Self.softwareGain
            let argScale = Self.tanhArgScale
            var samples = [Float](repeating: 0, count: count)
            for i in 0..<count {
                let v = channel[i] * gain
                samples[i] = v >= 0 ? tanhf(v * argScale) : -tanhf(-v * argScale)
            }
            self.onBuffer?(samples)
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioSourceError.engineStartFailed(underlying: error)
        }
    }

    func stop() {
        // Round 2 (Hyemi/Doyoon): tap 제거를 isRunning 무관하게 항상 시도.
        // engine 가 어떤 상태든 두 번 removeTap 해도 안전 (try? not needed; native API no-op when not installed)
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
        }
        onBuffer = nil
        converter = nil
        // Round 141 (Min H2): interruption observer 해제.
        if let token = interruptionObserver {
            NotificationCenter.default.removeObserver(token)
            interruptionObserver = nil
        }
    }

    deinit {
        // ARC 시점에 engine 가 자동 release 되지만 tap 명시 제거는 leak 방지.
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
        }
        if let token = interruptionObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    /// Round 141 (Min H2): 통화/Siri/알람 시 audio engine stale 방지.
    /// interruption began → stop tap; ended → start() 재시도는 호출자 책임 (UI 가 다시 측정 시작).
    func installInterruptionHandler(onInterruption: @escaping () -> Void) {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            if type == .began {
                self?.engine.inputNode.removeTap(onBus: 0)
                if self?.engine.isRunning == true {
                    self?.engine.stop()
                }
                onInterruption()
            }
        }
    }

    private func configureSession() throws {
        #if canImport(UIKit)
        let session = AVAudioSession.sharedInstance()
        do {
            // Round 1 (Doyoon, audit):
            // - .record 카테고리로 변경 (재생 불필요, .playAndRecord 의 출력 라우팅이 mic feedback 야기 가능)
            // - .defaultToSpeaker 제거 (입력 전용이므로 불필요, 일부 디바이스에서 입력 게인 부스트 유발)
            // - .measurement 모드는 유지 — AGC 비활성으로 정확한 신호 보존
            // Round 129 (실기기 Critical): [.allowBluetooth] 제거 — AirPods 등 BT 마이크에 라우팅되어
            // 시계 소리를 못 듣는 문제. iPhone 내장 마이크 강제. 사용자가 명시 선택하면 그때만 BT 허용.
            // Round 129f (실기기 spike 관찰): .measurement 복귀. AGC가 환경 spike(손동작 등)에 반응하여
            // signal level 흔들림 → onset detection 망가짐. .measurement = AGC off = 안정적 신호.
            // Round 158 (Lim 진단): iOS 26 의 Voice Isolation 이 `.record + .measurement` 를 override 함.
            // `.playAndRecord + .videoRecording` 으로 전환 — video pipeline 으로 system 이 인식하여
            // Voice Isolation 자동 우회. `.defaultToSpeaker` 는 input/output 분리 보장.
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker])
            // 사용자가 명시 선택한 외부 마이크만 적용. 기본은 iPhone 내장.
            try AudioInputManager.shared.applyPreferredToSession()
            // 추가 안전: builtInMic 명시 선택 + bottom data source (iPhone Air beamforming 회피).
            if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try? session.setPreferredInput(builtIn)
                // iPhone Air 4-mic array: bottom mic 명시 선택 (top mic + beamforming 회피).
                if let bottomSource = builtIn.dataSources?.first(where: { $0.orientation == .bottom }) {
                    try? builtIn.setPreferredDataSource(bottomSource)
                }
            }
            try session.setActive(true, options: [])
        } catch {
            throw AudioSourceError.sessionConfigurationFailed(underlying: error)
        }
        #endif
    }
}
