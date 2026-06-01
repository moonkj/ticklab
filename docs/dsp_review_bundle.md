# TickLab DSP — 오차(rate) 측정 알고리즘 리뷰 번들

> **외부 리뷰용 자급(self-contained) 문서.** 이 파일 하나만 Claude(또는 리뷰어)에게 주면 됩니다.
> iPhone 마이크로 기계식 시계 소리를 분석해 **rate(초/일) · beat error(ms) · amplitude(도) · 신뢰도(0~100)** 를
> 산출하는 **온디바이스** DSP 파이프라인. 측정 데이터는 외부 전송하지 않음(전부 on-device).
> 구성: ①알고리즘 개요(아래) + ②핵심 DSP 소스 전문(문서 하단 자동 첨부).

---

## 0. 리뷰 요청 (핵심)

기계식 시계 **rate 정확도/안정성** 개선점을 찾아주세요.
- 목표: 경쟁 앱(tickIQ) 수준 **±5 s/d**.
- 현재: 양호한 신호에선 근접하나, **저SNR(닫힌 케이스백 드레스워치 등)·짧은 측정**에서 ±20~30 s/d 변동.
- 레퍼런스 환경: iPhone Air + IWC Portugieser(검증됨).

## 1. 신호 체인 (stage 순서 — 파일별)

1. **오디오 캡처** — `AudioCapture` / `AudioInputManager` (48kHz, AVAudioEngine), `AudioSource` 추상화
2. **전처리 필터** — `Filters/` : PreEmphasis → BandPass → (NoiseFloor/Noise suppress) → Envelope
   - escapement tic/toc 충격음 대역 강조. `MultiBandEnvelope` / `SpectralFluxExtractor` / `MatchedFilter` 변형 존재.
3. **비트 검출** — `BeatDetector` (envelope 상의 onset, MAD threshold). 추상화 `BeatDetectorProtocol`,
   실험적 `CoreMLBeatDetector`.
4. **BPH 추정** — `BPHEstimator` : **autocorrelation 기반** lock + confidence(R(τ*)/R(0)).
   - ⚠️ **알려진 이슈**: envelope median-IOI 방식은 **+140 s/d phase bias** → rate 는 **무조건 `BPHEstimator.rawBph`(autocorrelation)** 사용. median-IOI 재도입 금지.
5. **rate 계산** — `LinearRegressionRate` : beat 타임스탬프 OLS 선형회귀 → 기대 주기 대비 drift(s/day).
6. **beat error** — `BeatErrorCalculator` : tic–toc 간격 비대칭(ms).
7. **amplitude** — `AmplitudeEstimator` : lift angle + impulse 간격(고신뢰 무브먼트만 노출).
8. **신뢰도** — `ConfidenceScorer` : SNR(20) + 측정시간(25) + BPH autocorr 신뢰(30) + tic/toc 분리(25) = 100.
   - 저하 원인 분류: `lowSNR`(SNR<14) / `shortDuration`(<30s) / `bphUncertain`.

전체 오케스트레이션은 `DSPPipeline` 에 있음(아래 소스 참고).

## 2. 두 가지 경로 (런타임 토글)

- **Legacy**: PLL/Template/OLS 풀 파이프라인.
- **Simplified (기본 ON, `useSimplifiedDSP`)**: tickIQ 스타일 — BP → envelope → MAD threshold → median IOI tight-3%.
  단순하지만 저신호에서 더 안정적이라는 가설로 기본 활성.

## 3. 게이팅 / 실패 규칙

- 무브먼트 DB `confidenceLabel`(veryHigh/high/medium/low/unverified) — high·veryHigh 만 amplitude 노출.
- `|rate| > 300 s/d` 또는 `beat error > 100ms` 는 측정 실패 처리(`DSPPipeline` guard).

## 4. 리뷰 포커스 (제안 — 자유롭게 추가)

1. **저SNR rate 안정성** — SNR<14dB(닫힌 케이스백)에서 ± 변동을 줄일 방법.
2. **BPH lock 견고성** — autocorrelation confidence 낮을 때 fallback 전략.
3. **simplified vs legacy** — 조건별 우월성, 둘을 융합(앙상블)할 여지.
4. **beat 검출 임계** — MAD threshold 적응성, 오검출/누락 트레이드오프.
5. **confidence 가중치(20/25/30/25)** — 실제 측정 품질과의 상관, 재보정 여지.
6. **윈도잉/측정시간** — 30s 고정 vs 적응형, cross-window consistency 활용.

## 5. 제약 (건드리지 말 것)

- envelope median-IOI rate(+140 s/d bias) — 이미 비활성, **재도입 금지**.
- DSP 변경은 **단위 테스트(fixture) 필수**.
- 측정 데이터 외부 전송 절대 금지.
- 성능 최적화(Metal/병렬화)는 Instruments 프로파일링 결과 없이 진행 금지.

---

# 핵심 DSP 소스 (전문)

> 아래는 `WatchAccuracyPro/Core/DSP/` 전체 소스입니다(리뷰어가 실제 구현을 직접 확인하도록 전부 첨부).

## `WatchAccuracyPro/Core/DSP/AmplitudeEstimator.swift`

```swift
import Foundation

/// 진폭(amplitude, 도) 추정.
///
/// 표준 horology 공식: amplitude_deg = (lift_angle_deg × T_beat) / (π × t_imp)
/// 여기서 t_imp 는 펄스(impulse) 지속시간으로, envelope 의 FWHM 으로 근사한다.
///
/// 한계:
/// - swiss lever 무브먼트에 대해서만 유의미. 코악시얼/스프링드라이브는 nil 반환.
/// - 폰 마이크 신호로는 t_imp 추정 정확도가 낮아 실측치와 ±20° 정도의 편차가 흔하다.
///   Week 7 베타 단계에서 Weishi 1900 ground truth로 캘리브레이션 예정.
enum AmplitudeEstimator {
    /// - Parameters:
    ///   - envelope: BandPass→Envelope 처리된 신호
    ///   - beats: 검출된 beat 이벤트
    ///   - sampleRate: 48000 권장
    ///   - liftAngleDegrees: 무브먼트 DB lookup 값. 모르면 nil 반환.
    ///   - escapement: coAxial / springDrive 면 nil 반환.
    /// - Returns: 진폭(도). 추정 불가 시 nil.
    static func estimate(
        envelope: [Float],
        beats: [BeatEvent],
        sampleRate: Double = 48_000,
        liftAngleDegrees: Double?,
        escapement: Escapement
    ) -> Double? {
        guard let liftAngle = liftAngleDegrees else { return nil }
        // Round 103 (DSP): siliconEscapement 는 swissLever 와 동작 동일 — 동일 공식 적용.
        guard escapement == .swissLever || escapement == .siliconEscapement else { return nil }
        guard beats.count >= 4 else { return nil }

        // T_beat 추정 — beats 사이 평균 간격
        var totalInterval: Double = 0
        for i in 0..<beats.count - 1 {
            totalInterval += beats[i + 1].timestampSeconds - beats[i].timestampSeconds
        }
        let tBeat = totalInterval / Double(beats.count - 1)
        guard tBeat > 0 else { return nil }

        // 각 beat의 envelope FWHM을 측정해 평균
        var fwhmEstimates: [Double] = []
        for beat in beats {
            let centerIdx = Int(beat.timestampSeconds * sampleRate)
            guard let fwhm = envelopeFWHM(envelope: envelope, centerIndex: centerIdx, sampleRate: sampleRate) else {
                continue
            }
            fwhmEstimates.append(fwhm)
        }
        guard !fwhmEstimates.isEmpty else { return nil }
        // 시작/끝 제외 robust 평균 (median)
        let sorted = fwhmEstimates.sorted()
        let tImp = sorted[sorted.count / 2]
        guard tImp > 0 else { return nil }

        let amplitude = (liftAngle * tBeat) / (.pi * tImp)
        // Round 158: 범위 50-400° 로 확장 (BandPass 6-15kHz 환경에서 FWHM 짧아져 amplitude 추정값 변동 큼).
        // 너무 좁은 범위는 amplitude 가 항상 nil → 사용자에게 진폭 안 보임.
        guard (50...400).contains(amplitude) else { return nil }
        // 360° 위 값은 추정 noise — 360 으로 clamp (실제 amplitude 가 360° 넘는 시계는 거의 없음).
        return min(amplitude, 360)
    }

    /// `centerIndex` 주변에서 local peak 의 envelope FWHM 을 초 단위로 반환.
    private static func envelopeFWHM(envelope: [Float], centerIndex: Int, sampleRate: Double) -> Double? {
        // 탐색 윈도우: ±20ms
        let windowSamples = Int(0.02 * sampleRate)
        let start = max(0, centerIndex - windowSamples)
        let end = min(envelope.count - 1, centerIndex + windowSamples)
        guard end > start else { return nil }
        var peakIdx = start
        var peak: Float = -.infinity
        for i in start...end where envelope[i] > peak {
            peak = envelope[i]
            peakIdx = i
        }
        guard peak > 0 else { return nil }
        let half = peak / 2
        var leftIdx = peakIdx
        var rightIdx = peakIdx
        while leftIdx > start && envelope[leftIdx] > half {
            leftIdx -= 1
        }
        while rightIdx < end && envelope[rightIdx] > half {
            rightIdx += 1
        }
        let fwhmSamples = Double(rightIdx - leftIdx)
        guard fwhmSamples > 0 else { return nil }
        return fwhmSamples / sampleRate
    }
}

```

## `WatchAccuracyPro/Core/DSP/AudioCapture.swift`

```swift
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
        // Min P0-4.1: AudioSession 비활성화 — 측정 종료 후 백그라운드 mic indicator(주황 점)
        //   잔존 + 배터리 drain 방지. notifyOthersOnDeactivation 으로 다른 앱(음악 등) 즉시 복귀.
        #if canImport(UIKit)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
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

```

## `WatchAccuracyPro/Core/DSP/AudioInputManager.swift`

```swift
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

```

## `WatchAccuracyPro/Core/DSP/AudioSource.swift`

```swift
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

```

## `WatchAccuracyPro/Core/DSP/BPHEstimator.swift`

```swift
import Accelerate
import Foundation

struct BPHEstimate: Equatable {
    let bph: Int                 // 표준 BPH로 스냅된 값 (18000/19800/21600/25200/28800/36000)
    let rawBph: Double           // autocorrelation peak에서 직접 계산한 값
    let confidence: Double       // 0~1, R(τ*) / R(0)
    let peakLagSeconds: Double   // autocorrelation peak이 잡힌 lag (초)
}

/// envelope 신호에서 시계의 BPH(시간당 비트수)를 추정한다.
///
/// 알고리즘 (사용자 보고된 ±129600 s/d 광기 수정):
/// - 표준 BPH 6개 (18000/21600/25200/28800/36000 + 19800)에 해당하는 lag 만 평가.
/// - 각 표준 lag 주변 ±1.5% 윈도우에서 max R 찾고, parabolic interpolation 으로 sub-sample 정밀도 확보.
/// - 후보 중 R 가 가장 큰 표준 BPH 채택.
/// - 최종 confidence (R/R0) 가 minConfidence 미만이면 nil 반환 — 신뢰 못 할 측정에 가짜 숫자 안 만들도록.
///
/// 이전 알고리즘은 "가장 짧은 유의미 peak" 를 inter-onset 으로 간주했는데, 실 환경 노이즈에서
/// 50ms 부근 spurious peak 에 끌려 72000 BPH 같은 광기의 값이 나옴. anchor-to-standard 로 차단.
enum BPHEstimator {
    /// Round 89 (김재철 Critical) + Round 102 (최용수 Critical): vintage BPH 추가.
    /// 8400 = 1900s pocket watch, 12000 = vintage Omega 30T2, 14400 = vintage Hamilton,
    /// 16200 = vintage Omega 30mm, 21000 = vintage AS calibre.
    /// 표준 6개 → 11개로 확장. 낮은 BPH 는 lag 가 길어 autocorrelation R/R0 낮아도 lock 시도 의미 있음.
    /// Round 122 (DSP High): Breguet Cal.502.3 35800 BPH 추가 — 없으면 36000 으로 snap해 ±4.8 s/d 오차.
    static let standardBPHs: [Int] = [8_400, 12_000, 14_400, 16_200, 18_000, 19_800, 21_000, 21_600, 25_200, 28_800, 35_800, 36_000]

    /// 이 값보다 R(τ*)/R(0) 이 낮으면 autocorrelation 신뢰 X.
    /// Round 30: 0.05→0.03. Round 129b: IWC SNR 16dB ONSETS 156인데도 lock 실패 → 0.008→0.003.
    /// 케이스 댐핑 강한 시계 R/R0 매우 낮음. nominalBphHint 있으면 false lock 거의 불가능 (±20% 범위 제한).
    static let minConfidence: Double = 0.003

    /// 진입점 — autocorrelation 우선 (flux signal 위에서 매우 robust).
    /// 사용자 보고: onset count 가 secondary peak 로 14% 초과 (110 vs 96 expected) → score-based 가 36000 잘못 픽.
    /// **autocorrelation 위주**: 표준 BPH lag 마다 R/R0 계산. 노이즈 onset 영향 받지 않음.
    /// onset-based 는 autocorrelation 결과 검증 보조.
    /// Round 34: `nominalBphHint` 추가 — 사용자가 무브먼트 선택했으면 그 nominal BPH 의 ±20% 안만 lock 후보.
    /// 36000 같은 잘못된 lock 차단 + 28800 정상 lock 회복.
    static func estimate(
        envelope: [Float],
        beats: [BeatEvent] = [],
        sampleRate: Double = 48_000,
        nominalBphHint: Int? = nil
    ) -> BPHEstimate? {
        let autoEst = estimateAutocorrelation(envelope: envelope, sampleRate: sampleRate, nominalBphHint: nominalBphHint)
        let onsetEst = beats.count >= 8 ? estimateFromOnsets(beats: beats, envelope: envelope, nominalBphHint: nominalBphHint) : nil

        // Round 32: 둘 다 있고 BPH 다를 때 — **onsetEst 우선** (이전: confidence 비교).
        // 사용자 보고 91/70/117/47 onsets 어떤 케이스도 lock 못함. 200Hz flux 위 autocorr 가 wrong
        // lag 잡은 가능성 큼 (lag granularity 거침). onsetEst (특히 IOI median fallback) 는 직접 IOI 분포
        // 보므로 사용자 실 device 케이스에서 더 robust. autoEst 는 confirm 역할만.
        switch (autoEst, onsetEst) {
        case (let a?, let o?):
            if a.bph == o.bph {
                return BPHEstimate(
                    bph: a.bph,
                    rawBph: a.rawBph,
                    confidence: Swift.min(1.0, a.confidence + o.confidence * 0.5),
                    peakLagSeconds: a.peakLagSeconds
                )
            }
            return o  // onsetEst 우선
        case (let a?, nil):  return a
        case (nil, let o?):  return o
        case (nil, nil):
            // Round 129c (사용자: 사람 귀에 들리는데 lock 실패): 최후 fallback — onset rate 단순 추정.
            // 임계값 다 통과 못한 marginal 신호도 결과는 반환. 신뢰도는 매우 낮음 (0.01).
            return fallbackFromOnsetRate(beats: beats, nominalBphHint: nominalBphHint)
        }
    }

    /// Round 131: fallback drift 50%/60% → 15%로 다시 엄격하게. garbage lock 방지가 우선.
    /// rate +216.5 s/d 같은 비정상값은 BPH 잘못 lock → rate 잘못 계산의 결과.
    /// fallback 통과 못해 nil 반환 시 → lockFailure UI → 사용자에게 "재측정" 안내 (정확함).
    private static func fallbackFromOnsetRate(beats: [BeatEvent], nominalBphHint: Int?) -> BPHEstimate? {
        guard beats.count >= 20 else { return nil }
        let timeSpan = beats.last!.timestampSeconds - beats.first!.timestampSeconds
        guard timeSpan >= 5 else { return nil }
        let onsetRate = Double(beats.count) / timeSpan
        let rawBph = onsetRate * 1800
        let candidates = nominalBphHint.map { hint in
            hint > 0 ? standardBPHs.filter { abs(Double($0 - hint)) / Double(hint) <= 0.20 } : standardBPHs
        } ?? standardBPHs
        let snapped = nearestStandardBPH(rawBph, candidates: candidates)
        let drift = abs(Double(snapped) - rawBph) / Double(snapped)
        // Round 131 (사용자 garbage rate +216 보고): drift 50% → 15% 엄격.
        // 잘못된 lock 으로 부정확 rate 출력하는 것보다 lockFailure 가 사용자에게 더 정직.
        guard drift < 0.15 else { return nil }
        return BPHEstimate(
            bph: snapped,
            rawBph: rawBph,
            confidence: 0.05,
            peakLagSeconds: 1.0 / onsetRate
        )
    }

    /// **Score-based BPH 검출** — robust to noisy onset detection.
    /// 각 표준 BPH 의 expected interval 에 대해, 실제 intervals 중 ±10% 이내인 개수를 셈.
    /// 가장 매칭 많은 BPH 가 winner.
    /// 사용자 보고: median 방식이 secondary-peak 노이즈에 약했음. score 방식은 노이즈 자연 제거.
    static func estimateFromOnsets(beats: [BeatEvent], envelope: [Float], nominalBphHint: Int? = nil) -> BPHEstimate? {
        guard beats.count >= 8 else { return nil }
        var intervals: [Double] = []
        intervals.reserveCapacity(beats.count - 1)
        for i in 1..<beats.count {
            intervals.append(beats[i].timestampSeconds - beats[i - 1].timestampSeconds)
        }
        // Round 129d (사용자 측정 안됨): valid filter 대폭 완화 — 0.060→0.040, 0.500→0.800.
        // 36000 BPH (10ms IOI?) ~ 8400 BPH (430ms IOI) 모두 포함. jitter 큰 환경 흡수.
        let valid = intervals.filter { $0 >= 0.040 && $0 <= 0.800 }
        guard valid.count >= 6 else { return nil }

        // 각 표준 BPH 점수 계산.
        // Round 30 fix: tie (예: 21600 vs 19800 둘 다 17/17 matches) 시 IOI mean drift 작은 candidate 채택.
        // 이전엔 standardBPHs 순서상 먼저인 19800 잘못 채택해 21600 lock 회귀 유발.
        // Round 34: nominalBphHint 있으면 ±20% 안의 표준 BPH 만 후보 — 잘못된 lock (예: 28800 시계의 36000 lock) 차단.
        let candidates: [Int] = nominalBphHint.map { hint in
            // Round 104 (Swift High): hint=0 이면 division by zero → NaN → 모든 후보 차단.
            // quartz(bph=0) 는 Round 98 에서 이미 start() 에서 차단되므로 방어 가드.
            hint > 0 ? standardBPHs.filter { abs(Double($0 - hint)) / Double(hint) <= 0.20 } : standardBPHs
        } ?? standardBPHs
        struct CandidateScore { let bph: Int; let matches: [Double]; let count: Int; let driftFromExpected: Double }
        var bestCandidate: CandidateScore?
        for bph in candidates {
            let expected = 3600.0 / Double(bph)
            let tolerance = expected * 0.10  // ±10%
            let matches = valid.filter { abs($0 - expected) <= tolerance }
            guard !matches.isEmpty else { continue }
            let matchMean = matches.reduce(0, +) / Double(matches.count)
            let drift = abs(matchMean - expected) / expected
            let candidate = CandidateScore(bph: bph, matches: matches, count: matches.count, driftFromExpected: drift)
            if let cur = bestCandidate {
                if matches.count > cur.count
                   || (matches.count == cur.count && drift < cur.driftFromExpected) {
                    bestCandidate = candidate
                }
            } else {
                bestCandidate = candidate
            }
        }

        // Round 37: matchRatio 0.30 → 0.20 (원래 값 복귀). tickIQ "정확치는 않지만 측정 되긴 함"
        // 동작 흉내 — marginal 신호도 통과. nominal-guided + drift guard 가 광기 lock 차단.
        if let best = bestCandidate, best.count >= 4 {
            let matchRatio = Double(best.count) / Double(valid.count)
            if matchRatio >= 0.20 {
                let sortedMatches = best.matches.sorted()
                let preciseInterval = sortedMatches[sortedMatches.count / 2]
                let rawBph = 3600.0 / preciseInterval
                let mean = best.matches.reduce(0, +) / Double(best.count)
                let variance = best.matches.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(best.count)
                let cv = sqrt(variance) / mean
                let consistencyConf = Swift.max(0, Swift.min(1, 1 - cv * 5))
                return BPHEstimate(
                    bph: best.bph,
                    rawBph: rawBph,
                    confidence: matchRatio * consistencyConf,
                    peakLagSeconds: preciseInterval
                )
            }
        }

        // Round 30 — IOI-median fallback.
        // 사용자 보고: 91 onsets / 12s 인데도 BPH lock 실패. 가설: autocorrelation 의 lag granularity
        // 거침 + tolerance window jitter 흡수 부족. onset 풍부할 때만 (>= 30) 진입 — 적은 onset 의 합성
        // 테스트가 fallback 에 진입해 잘못 lock 하는 회귀 차단.
        // Round 34: candidates (nominalBphHint 적용) 안에서 nearest BPH 찾기 — 사용자 신호 잡힌 BPH 가
        // 잘못된 standard (예: 36000) 로 snap 되는 case 차단.
        // Round 129c (사용자: "사람 귀에 들리는데"): 매우 완화. 사람 청각 검증된 신호는 무조건 lock 시도.
        guard valid.count >= 15 else { return nil }
        let sortedAll = valid.sorted()
        let medianIOI = sortedAll[sortedAll.count / 2]
        let rawBph = 3600.0 / medianIOI
        let snapped = nearestStandardBPH(rawBph, candidates: candidates)
        let drift = abs(Double(snapped) - rawBph) / Double(snapped)
        // 10% → 18% 완화 (jitter 큰 환경).
        guard drift < 0.18 else { return nil }
        let expectedAtSnapped = 3600.0 / Double(snapped)
        // tolerance 10% → 15% 완화.
        let tolerance = expectedAtSnapped * 0.15
        let near = valid.filter { abs($0 - expectedAtSnapped) <= tolerance }.count
        let conf = Double(near) / Double(valid.count)
        // 0.25 → 0.12 완화 (사람 귀에 들리는 신호 무조건 lock).
        guard conf >= 0.12 else { return nil }
        return BPHEstimate(
            bph: snapped,
            rawBph: rawBph,
            confidence: conf,
            peakLagSeconds: medianIOI
        )
    }

    static func estimateAutocorrelation(envelope: [Float], sampleRate: Double = 48_000, nominalBphHint: Int? = nil) -> BPHEstimate? {
        guard envelope.count > Int(sampleRate * 0.5) else { return nil }
        // Round 34: nominalBphHint 있으면 ±20% 안의 표준 BPH 만 후보.
        let candidates: [Int] = nominalBphHint.map { hint in
            // Round 104 (Swift High): hint=0 이면 division by zero → NaN → 모든 후보 차단.
            // quartz(bph=0) 는 Round 98 에서 이미 start() 에서 차단되므로 방어 가드.
            hint > 0 ? standardBPHs.filter { abs(Double($0 - hint)) / Double(hint) <= 0.20 } : standardBPHs
        } ?? standardBPHs

        // DC + slow drift 제거 — 단순 mean 빼는 대신 moving average 빼서 baseline drift 까지 제거.
        // 마이크 핸들링이나 환경 변화로 envelope 가 천천히 변하면 short-lag R 가 그 drift 에 압도됨.
        // window = 50ms (= 0.05 × sampleRate) 로 watch period 보다 짧게.
        let detrendWindow = max(1, Int(sampleRate * 0.05))
        var centered = [Float](repeating: 0, count: envelope.count)
        Self.subtractMovingAverage(envelope, into: &centered, window: detrendWindow)

        var r0: Float = 0
        vDSP_dotpr(centered, 1, centered, 1, &r0, vDSP_Length(centered.count))
        guard r0 > 0 else { return nil }

        // 각 표준 BPH 의 inter-beat lag 에서 R 측정.
        var lagCandidates: [(bph: Int, lag: Int, r: Float, lagD: Double, rD: Float)] = []
        for bph in candidates {
            let periodSeconds = 3600.0 / Double(bph)
            let centerLag = Int((periodSeconds * sampleRate).rounded())
            // Round 130 (Chen P5): nominalBphHint 있으면 ±5% (lag granularity 보완), 없으면 ±1.5% (안전).
            // hint 있으면 candidates 이미 ±20%로 제한돼서 인접 표준 lock 위험 없음.
            let halfPct: Double = nominalBphHint != nil ? 0.05 : 0.015
            let halfWindow = max(2, Int(Double(centerLag) * halfPct))
            let lo = max(1, centerLag - halfWindow)
            let hi = min(envelope.count - 1, centerLag + halfWindow)
            guard lo <= hi else { continue }

            var localMaxR: Float = -.infinity
            var localMaxLag = lo
            centered.withUnsafeBufferPointer { ptr in
                let base = ptr.baseAddress!
                for lag in lo...hi {
                    let count = envelope.count - lag
                    guard count > 0 else { return }
                    var r: Float = 0
                    vDSP_dotpr(base, 1, base.advanced(by: lag), 1, &r, vDSP_Length(count))
                    if r > localMaxR {
                        localMaxR = r
                        localMaxLag = lag
                    }
                }
            }

            // parabolic interpolation around localMaxLag (조금 더 정밀한 BPH 추정)
            let lagD: Double
            if localMaxLag > lo && localMaxLag < hi {
                var rL: Float = 0, rR: Float = 0
                centered.withUnsafeBufferPointer { ptr in
                    let base = ptr.baseAddress!
                    let cL = envelope.count - (localMaxLag - 1)
                    let cR = envelope.count - (localMaxLag + 1)
                    if cL > 0 {
                        vDSP_dotpr(base, 1, base.advanced(by: localMaxLag - 1), 1, &rL, vDSP_Length(cL))
                    }
                    if cR > 0 {
                        vDSP_dotpr(base, 1, base.advanced(by: localMaxLag + 1), 1, &rR, vDSP_Length(cR))
                    }
                }
                let denom = rL - 2 * localMaxR + rR
                let delta = denom != 0 ? 0.5 * (rL - rR) / denom : 0
                lagD = Double(localMaxLag) + Double(delta)
            } else {
                lagD = Double(localMaxLag)
            }

            lagCandidates.append((bph: bph, lag: localMaxLag, r: localMaxR, lagD: lagD, rD: localMaxR))
        }

        // R 이 가장 큰 표준 BPH 후보 찾기.
        guard let max = lagCandidates.max(by: { $0.r < $1.r }), max.r > 0 else {
            return nil
        }
        // Round 30: 'smaller BPH preferred' 는 정수배 lag (harmonic) 관계일 때만 fundamental 선호.
        // 21600 (lag 33) 와 19800 (lag 36) 처럼 인접 표준은 정수배 아님 → 단순히 max.r 채택.
        // 이전 'strong.max(by: smaller BPH)' 는 21600 신호의 19800 weak peak 잘못 채택해 회귀 유발.
        let strongThreshold = max.r * 0.85
        let strong = lagCandidates.filter { $0.r >= strongThreshold }
        let chosen: (bph: Int, lag: Int, r: Float, lagD: Double, rD: Float)
        if strong.count > 1 {
            let sortedByLag = strong.sorted(by: { $0.lag < $1.lag })
            let shortest = sortedByLag[0]
            let isHarmonicFamily = sortedByLag.dropFirst().allSatisfy { c in
                let ratio = Double(c.lag) / Double(shortest.lag)
                return abs(ratio - ratio.rounded()) < 0.05 && ratio >= 1.8
            }
            chosen = isHarmonicFamily ? shortest : max  // fundamental vs 인접 모호성
        } else {
            chosen = max
        }

        var confidence = Double(chosen.r / r0)
        var bestLagD = chosen.lagD
        var bestStandardBPH = chosen.bph

        // 표준 BPH 매칭이 약하면 — 60-500ms 전체 범위 sweep 으로 peak 찾기 시도.
        // 사용자 보고: 일부 시계는 표준 BPH ±1.5% 윈도우 밖에 lock 될 수 있음 (drift 큰 경우).
        if confidence < minConfidence * 2 {
            if let sweepBest = sweepBestLag(centered: centered, sampleRate: sampleRate) {
                let sweepConf = Double(sweepBest.r / r0)
                if sweepConf > confidence {
                    confidence = sweepConf
                    bestLagD = sweepBest.lagD
                    bestStandardBPH = nearestStandardBPH(3600.0 / (sweepBest.lagD / sampleRate), candidates: candidates)
                }
            }
        }

        // 신호 너무 약하면 nil — 광기의 숫자 만들지 않도록.
        guard confidence >= minConfidence else { return nil }

        let periodSeconds = bestLagD / sampleRate
        let rawBph = 3_600.0 / periodSeconds
        // Round 37 (tickIQ 측정 됨, 우리 strict guard 가 정상 측정 차단): 12% → 18% 추가 완화 (사용자 보고 측정 안됨).
        // 광기 lock (drift 50%+) 는 차단 유지, marginal lock 은 통과 허용.
        let driftFromStandard = abs(rawBph - Double(bestStandardBPH)) / Double(bestStandardBPH)
        guard driftFromStandard < 0.18 else { return nil }
        return BPHEstimate(
            bph: bestStandardBPH,
            rawBph: rawBph,
            confidence: confidence,
            peakLagSeconds: periodSeconds
        )
    }

    /// 60ms–1000ms 범위에서 가장 강한 peak 검색 (sweep). 표준 BPH 매칭이 실패할 때 fallback.
    /// Round 122 (DSP Critical): 8400 BPH lag = 857ms — 500ms 상한에서 못 잡히던 버그 수정.
    private static func sweepBestLag(centered: [Float], sampleRate: Double) -> (lagD: Double, r: Float)? {
        let minLag = max(1, Int(sampleRate * 0.060))   // 60ms = 60000 BPH
        let maxLag = min(centered.count - 1, Int(sampleRate * 1.000))  // 1000ms → 3600 BPH cover
        guard minLag < maxLag else { return nil }
        var bestR: Float = -.infinity
        var bestLag = minLag
        var rValues = [Float]()
        rValues.reserveCapacity(maxLag - minLag + 1)
        centered.withUnsafeBufferPointer { ptr in
            let base = ptr.baseAddress!
            for lag in minLag...maxLag {
                let count = centered.count - lag
                guard count > 0 else { break }
                var r: Float = 0
                vDSP_dotpr(base, 1, base.advanced(by: lag), 1, &r, vDSP_Length(count))
                rValues.append(r)
                if r > bestR { bestR = r; bestLag = lag }
            }
        }
        // parabolic interpolation around best
        let idx = bestLag - minLag
        let lagD: Double
        if idx > 0, idx < rValues.count - 1 {
            let yL = rValues[idx - 1], yC = rValues[idx], yR = rValues[idx + 1]
            let denom = yL - 2 * yC + yR
            let delta = denom != 0 ? 0.5 * (yL - yR) / denom : 0
            lagD = Double(bestLag) + Double(delta)
        } else {
            lagD = Double(bestLag)
        }
        return (lagD: lagD, r: bestR)
    }

    /// 입력 신호에서 moving-average 를 빼 baseline drift 를 제거.
    /// prefix sum 기반 O(n) — edge effect 자동 처리.
    static func subtractMovingAverage(_ input: [Float], into output: inout [Float], window: Int) {
        let n = input.count
        guard n > 0, output.count >= n else { return }
        let half = max(1, window / 2)
        var prefix = [Float](repeating: 0, count: n + 1)
        for i in 0..<n { prefix[i + 1] = prefix[i] + input[i] }
        for i in 0..<n {
            let lo = max(0, i - half)
            let hi = min(n - 1, i + half)
            let sum = prefix[hi + 1] - prefix[lo]
            let count = Float(hi - lo + 1)
            let avg = count > 0 ? sum / count : 0
            output[i] = input[i] - avg
        }
    }

    static func nearestStandardBPH(_ raw: Double, candidates: [Int]? = nil) -> Int {
        let pool = candidates ?? standardBPHs
        var bestDiff = Double.infinity
        var bestBph = pool.first ?? standardBPHs[0]
        for bph in pool {
            let d = abs(raw - Double(bph))
            if d < bestDiff {
                bestDiff = d
                bestBph = bph
            }
        }
        return bestBph
    }
}

```

## `WatchAccuracyPro/Core/DSP/BeatDetector.swift`

```swift
import Accelerate
import Foundation

enum BeatType: String, Sendable {
    case tic
    case toc
}

struct BeatEvent: Equatable, Sendable {
    /// 신호 시작 시각 기준 onset 위치 (초).
    let timestampSeconds: Double
    let type: BeatType
    /// envelope peak 값 (정규화 X) — confidence/amplitude 계산에 활용.
    let energy: Double
}

/// envelope에서 onset을 추출해 tic/toc parity를 부여한다.
enum BeatDetector {
    /// Percentile 기반 절대 임계 — 균형점 튜닝.
    /// 사용자 보고: 0.65/3.0 너무 엄격해 SNR 8dB (ratio 2.5) 에서 모든 tic 거부 → onsets 0.
    /// **0.55/1.8 로 완화** — marginal 신호도 수용. score-based BPH 가 노이즈 제거 담당.
    // Round 129 (실기기 피드백): 케이스백 닫힌 시계(IWC 등) onset 감지율 43% → 임계 0.45→0.35 완화.
    // 낮은 SNR 환경에서 더 많은 beat 감지. false positive는 BPH autocorr 단계에서 필터링.
    static func detectOnsets(
        envelope: [Float],
        sampleRate: Double = 48_000,
        thresholdRatio: Float = 0.25,
        // Round 155 (사용자 보고: 451 beats/30s = 15/s, 28800 의 ~2배 → sub-pulse 가 별도 onset 으로 잡힘).
        // 28800 IOI 125ms → refractory 100ms 로 늘려 sub-pulse(lock/impulse/drop) 차단.
        refractoryMs: Double = 100.0
    ) -> [BeatEvent] {
        guard envelope.count > 0 else { return [] }

        // Round 158: Round 156 이전 working state 복원 — percentile threshold.
        // 사용자 IWC 측정에서 adaptive threshold 가 BPH lock 차단 → revert.
        let originalSorted = envelope.sorted()
        let p95Idx = min(originalSorted.count - 1, (originalSorted.count * 95) / 100)
        let p95 = originalSorted[p95Idx]
        let clipCeiling = max(p95 * 2, 1e-9)
        let clipped: [Float] = envelope.map { min($0, clipCeiling) }

        let sorted = clipped.sorted()
        let bottomHalfCount = max(1, sorted.count / 2)
        let p25BottomIdx = max(0, bottomHalfCount / 4)
        let noiseFloor = sorted[p25BottomIdx]
        let topStart = max(0, sorted.count - max(1, sorted.count / 20))
        let topCount = sorted.count - topStart
        let peak = sorted[topStart + topCount / 2]
        guard peak > noiseFloor * 1.2 else { return [] }
        let threshold = noiseFloor + thresholdRatio * (peak - noiseFloor)

        let refractorySamples = Int(refractoryMs / 1_000 * sampleRate)
        var onsets: [(idx: Int, energy: Float)] = []
        var i = 1
        while i < clipped.count - 1 {
            let v = clipped[i]
            if v >= threshold && v >= clipped[i - 1] && v >= clipped[i + 1] {
                onsets.append((i, v))
                i += refractorySamples
            } else {
                i += 1
            }
        }

        // tic/toc parity 부여
        var events: [BeatEvent] = []
        events.reserveCapacity(onsets.count)
        for (idx, onset) in onsets.enumerated() {
            let type: BeatType = idx.isMultiple(of: 2) ? .tic : .toc
            events.append(BeatEvent(
                timestampSeconds: Double(onset.idx) / sampleRate,
                type: type,
                energy: Double(onset.energy)
            ))
        }
        return events
    }

    /// Round 156 (Aoki + Wang + Petrov 토론): sub-pulse 통합.
    /// IWC 35111 / SW300 등 modern swissLever 는 lock-impulse-drop 3-stage 충격이
    /// 1.8-3.0ms 간격으로 발생 → 5ms flux frame 에서 별도 onset 으로 분리.
    /// 사용자 451 beats/30s = 1.88× 정상 (240) → 약 50% beat 이 2 onset 으로 split.
    ///
    /// 동작: nominalBph 의 IOI 대비 30% 이하 간격(IOI<0.3) 의 인접 onset 쌍을 cluster.
    /// energy-weighted centroid 로 단일 onset 으로 통합. 후속 BPH/rate 분석 안정화.
    ///
    /// nominalBph nil 이면 no-op (regression 안전망).
    static func clusterSubPulses(beats: [BeatEvent], nominalBph: Int?) -> [BeatEvent] {
        guard let bph = nominalBph, bph > 0, beats.count >= 2 else { return beats }
        let expectedIOI = 3600.0 / Double(bph)
        // Round 158 (tickIQ 분석 후): cluster gate 1.2×. user IWC 9.9 Hz onset 패턴 = sub-pulse 검출 →
        // 1.2× gate (9.6 Hz) 가 cluster fire → sub-pulse merge → IOI median 125ms → BPH 28800 lock.
        let duration = beats.last!.timestampSeconds - beats.first!.timestampSeconds
        if duration > 0.5 {
            let observedRate = Double(beats.count - 1) / duration
            let nominalRate = Double(bph) / 3600.0
            if observedRate < nominalRate * 1.2 {
                return beats
            }
        }
        // 30% 이하 간격 = sub-pulse 후보 (28800 의 경우 125ms × 0.3 = 37.5ms)
        let clusterThreshold = expectedIOI * 0.30
        var clustered: [BeatEvent] = []
        clustered.reserveCapacity(beats.count)
        // Round 156 (Min #1 fix): 누적 group span 가드 — 그룹 시작 대비 50% × expectedIOI 초과 금지.
        // 그리디 체이닝(sub-pulse 4+ 연속) 으로 정상 beat 흡수 위험 차단.
        let maxGroupSpan = expectedIOI * 0.50
        var i = 0
        while i < beats.count {
            var groupEnd = i
            let groupStart = beats[i].timestampSeconds
            // 연속된 sub-pulse 들 그룹화 — 그룹 내 last 대비 다음이 threshold 안 + 그룹 시작 대비 maxGroupSpan 안.
            while groupEnd + 1 < beats.count,
                  beats[groupEnd + 1].timestampSeconds - beats[groupEnd].timestampSeconds <= clusterThreshold,
                  beats[groupEnd + 1].timestampSeconds - groupStart <= maxGroupSpan {
                groupEnd += 1
            }
            if groupEnd == i {
                clustered.append(beats[i])
            } else {
                // Energy-weighted centroid — lock impulse (가장 강함) 위치에 가깝게 통합.
                var sumWeight: Double = 0
                var sumWeightedTime: Double = 0
                var maxEnergy: Double = 0
                for j in i...groupEnd {
                    let w = max(beats[j].energy, 1e-9)
                    sumWeight += w
                    sumWeightedTime += beats[j].timestampSeconds * w
                    if beats[j].energy > maxEnergy { maxEnergy = beats[j].energy }
                }
                let centroidTime = sumWeight > 0 ? sumWeightedTime / sumWeight : beats[i].timestampSeconds
                clustered.append(BeatEvent(
                    timestampSeconds: centroidTime,
                    type: beats[i].type,  // parity 는 group 첫 onset 의 type 유지 (refineParity 가 재할당)
                    energy: maxEnergy
                ))
            }
            i = groupEnd + 1
        }
        // tic/toc parity 재할당 — clustering 후 onset 개수 줄었으므로 인덱스 기반으로 재계산.
        var refinedParity: [BeatEvent] = []
        refinedParity.reserveCapacity(clustered.count)
        for (idx, b) in clustered.enumerated() {
            let type: BeatType = idx.isMultiple(of: 2) ? .tic : .toc
            refinedParity.append(BeatEvent(
                timestampSeconds: b.timestampSeconds,
                type: type,
                energy: b.energy
            ))
        }
        return refinedParity
    }

    /// Round 39: Audio-rate parabolic interpolation 으로 onset timestamp sub-sample 정밀도 부여.
    ///
    /// 사용자 보고: live rate +0.0 s/d — 200Hz flux 의 frame quantization (5ms) 한계.
    /// 28800 BPH IOI = 25 frame, 1 frame 변화가 ±1100 s/d 변동 → 작은 drift quantize to 0.
    ///
    /// 동작: 각 onset 의 frame-level timestamp 를 48kHz envelope 위에서 ±searchWindowMs 영역의
    /// 실제 peak 위치로 refine. parabolic interpolation 으로 sub-sample 정밀도.
    /// → timestamp 정밀도 5ms → ~0.02ms (250× 향상) → rate 정밀도 ±5 s/d 이하 가능.
    static func refineTimestamps(
        beats: [BeatEvent],
        envelope: [Float],
        envelopeSampleRate: Double,
        searchWindowMs: Double = 10
    ) -> [BeatEvent] {
        guard !envelope.isEmpty, !beats.isEmpty else { return beats }
        let searchSamples = max(1, Int(searchWindowMs / 1_000 * envelopeSampleRate))
        var refined: [BeatEvent] = []
        refined.reserveCapacity(beats.count)
        for beat in beats {
            let approxIdx = Int(beat.timestampSeconds * envelopeSampleRate)
            let lo = max(1, approxIdx - searchSamples)
            let hi = min(envelope.count - 2, approxIdx + searchSamples)
            guard lo < hi else {
                refined.append(beat)
                continue
            }
            // 1) 영역 안 max 위치
            var maxIdx = lo
            var maxVal: Float = envelope[lo]
            for i in lo...hi where envelope[i] > maxVal {
                maxVal = envelope[i]
                maxIdx = i
            }
            // 2) parabolic interpolation around maxIdx (sub-sample fraction)
            //    y(t) = y_C + (y_R - y_L)/2 · t + (y_L - 2y_C + y_R)/2 · t²
            //    derivative = 0 at t* = -(y_R - y_L) / (2(y_L - 2y_C + y_R)) = 0.5(y_L - y_R)/denom
            let preciseIdx: Double
            if maxIdx > 0 && maxIdx < envelope.count - 1 {
                let yL = envelope[maxIdx - 1]
                let yC = envelope[maxIdx]
                let yR = envelope[maxIdx + 1]
                let denom = yL - 2 * yC + yR
                let delta: Double = denom != 0 ? Double(0.5 * (yL - yR) / denom) : 0
                preciseIdx = Double(maxIdx) + delta.clamped(to: -1...1)  // safety: ±1 sample 까지만
            } else {
                preciseIdx = Double(maxIdx)
            }
            let preciseTimestamp = preciseIdx / envelopeSampleRate
            refined.append(BeatEvent(
                timestampSeconds: preciseTimestamp,
                type: beat.type,
                energy: Double(maxVal)
            ))
        }
        return refined
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

```

## `WatchAccuracyPro/Core/DSP/BeatDetectorProtocol.swift`

```swift
import Foundation

/// Beat 검출 알고리즘의 추상화.
/// Phase 1 의 Onset-based 검출(`OnsetBeatDetector`) 와 Phase 2 의 CoreML 검출(`CoreMLBeatDetector`) 가 같은 인터페이스를 만족.
protocol BeatDetecting {
    func detect(envelope: [Float], sampleRate: Double) -> [BeatEvent]
}

/// 기존 `BeatDetector` 정적 메서드를 protocol 인스턴스로 감싸 사용.
struct OnsetBeatDetector: BeatDetecting {
    func detect(envelope: [Float], sampleRate: Double) -> [BeatEvent] {
        BeatDetector.detectOnsets(envelope: envelope, sampleRate: sampleRate)
    }
}

```

## `WatchAccuracyPro/Core/DSP/BeatErrorCalculator.swift`

```swift
import Foundation

/// tic→toc 간격(T1)과 toc→tic 간격(T2)의 비대칭으로부터 beat error를 계산한다.
/// beat error = |mean(T1) - mean(T2)| × 1000 (단위 ms).
/// 이상적으로는 두 간격이 같아 0ms, 0.5ms 이상이면 일반 조정 권장.
enum BeatErrorCalculator {
    /// - Parameter beats: 시간 오름차순 beat events. tic/toc 가 번갈아 등장한다고 가정.
    /// Round 30: missing tic 으로 한쪽 IOI 가 부풀려지는 case 대비 median 기반 + valid filter.
    /// 사용자 보고: 70 onsets/12s 의 mean-based beat error 가 30ms 넘게 부풀려져 BPH lock 자체 실패.
    static func beatErrorMs(beats: [BeatEvent]) -> Double? {
        guard beats.count >= 4 else { return nil }
        var t1: [Double] = []  // tic→toc
        var t2: [Double] = []  // toc→tic
        for i in 0..<beats.count - 1 {
            let interval = beats[i + 1].timestampSeconds - beats[i].timestampSeconds
            if beats[i].type == .tic {
                t1.append(interval)
            } else {
                t2.append(interval)
            }
        }
        // Valid filter — missing beat 로 인한 250ms+ IOI 등 outlier 제거.
        let validT1 = t1.filter { $0 >= 0.060 && $0 <= 0.500 }.sorted()
        let validT2 = t2.filter { $0 >= 0.060 && $0 <= 0.500 }.sorted()
        guard !validT1.isEmpty, !validT2.isEmpty else { return nil }
        let median1 = validT1[validT1.count / 2]
        let median2 = validT2[validT2.count / 2]
        return abs(median1 - median2) * 1_000
    }
}

```

## `WatchAccuracyPro/Core/DSP/ConfidenceScorer.swift`

```swift
import Foundation

struct ConfidenceInputs {
    let snrDB: Double
    let durationSeconds: Double
    let bphAutocorrelationConfidence: Double  // 0~1, R(τ*)/R(0)
    let beatCount: Int
    let beatErrorMs: Double?
}

/// 측정 신뢰도(0~100)를 산출.
/// Round 110 (DSP 연구팀): 가중치 재조정 — SNR 과중 완화, BPH 정확도 강화.
/// 가중치 합산 (합계 100):
///   - SNR(dB): 12dB 기준, 22dB 상한으로 낮춤 (이전 25dB는 실내에서도 드물었음) → 20점
///   - 측정 시간: 30s 이상 부분 점수, 120s+ = 25점 (유지)
///   - BPH autocorrelation 신뢰도: lock 품질 → 30점 (이전 25점에서 상향)
///   - tic/toc 분리도 (beat error 0~2ms) → 25점 (이전 20점에서 상향)
/// 합계: 20+25+30+25 = 100
enum ConfidenceScorer {
    static func score(_ inputs: ConfidenceInputs) -> Int {
        var s = 0.0

        // SNR — Round 110: 상한 25→22dB, 가중치 30→20점.
        // Round 129 (실기기 피드백): 케이스백 닫힌 드레스워치(IWC/Longines 등)는 SNR이 낮음.
        // 12→10dB 완화. 10dB 이하는 노이즈 환경으로 간주.
        let snrLow = 10.0
        let snrHigh = 22.0
        if inputs.snrDB >= snrHigh {
            s += 20
        } else if inputs.snrDB > snrLow {
            let normalized = (inputs.snrDB - snrLow) / (snrHigh - snrLow)
            s += 20 * normalized
        }

        // Duration — 30초 = 10점, 60초 = 17점, 120초+ = 25점 (사이 linear).
        let dur = inputs.durationSeconds
        if dur >= 120 {
            s += 25
        } else if dur >= 60 {
            s += 17 + 8 * (dur - 60) / 60
        } else if dur >= 30 {
            s += 10 + 7 * (dur - 30) / 30
        } else if dur >= 10 {
            s += 5 + 5 * (dur - 10) / 20
        }

        // BPH autocorrelation confidence — Round 110: 25→30점 (lock 품질 핵심 지표).
        let bphConf = max(0, min(1, inputs.bphAutocorrelationConfidence))
        s += 30 * bphConf

        // tic/toc 분리도 — Round 110: 20→25점 (beat error 0ms 는 무브먼트 상태 매우 양호).
        if let beatError = inputs.beatErrorMs {
            let normalized = max(0, min(1, beatError / 2.0))  // 2ms 이상이면 0점
            s += 25 * (1 - normalized)
        }

        return min(100, Int(s.rounded()))
    }

    /// T-02: 신뢰도 저하의 주된 원인 분류 — UI 가 개선 안내(HelpCard)로 노출. 우선순위 순.
    /// `bphConfidence` 가 주어지면(DSP 경로) 직접 판정, nil(결과화면 경로)이면
    /// SNR·측정시간으로 설명되지 않는 저점수를 BPH lock 문제로 추정한다.
    static func reasons(snrDB: Double, durationSeconds: Double,
                        confidenceScore: Int, bphConfidence: Double? = nil) -> [ConfidenceReason] {
        var out: [ConfidenceReason] = []
        if snrDB < 14 { out.append(.lowSNR) }
        if durationSeconds < 30 { out.append(.shortDuration) }
        if let c = bphConfidence {
            if c < 0.6 { out.append(.bphUncertain) }
        } else if confidenceScore < 70, snrDB >= 14, durationSeconds >= 30 {
            out.append(.bphUncertain)
        }
        return out
    }
}

/// 신뢰도 저하 원인 — 낮은 신뢰도일 때 사용자에게 개선 방법을 안내(T-02).
enum ConfidenceReason: String, CaseIterable, Hashable, Sendable {
    case lowSNR
    case shortDuration
    case bphUncertain

    /// Localizable.strings 키 (Hard Rule #3: 인라인 문자열 금지).
    var localizationKey: String {
        switch self {
        case .lowSNR:        return "confidence.reason.lowSNR"
        case .shortDuration: return "confidence.reason.shortDuration"
        case .bphUncertain:  return "confidence.reason.bphUncertain"
        }
    }
    var icon: String {
        switch self {
        case .lowSNR:        return "speaker.wave.2"
        case .shortDuration: return "clock"
        case .bphUncertain:  return "waveform.badge.magnifyingglass"
        }
    }
}

```

## `WatchAccuracyPro/Core/DSP/CoreMLBeatDetector.swift`

```swift
import CoreML
import Foundation

/// CoreML 기반 beat 검출기 hook.
///
/// Phase 2 베타: 모델 파일 (`BeatDetector.mlmodel`) 이 번들에 포함된 경우에만 활성화.
/// 모델 출력은 frame 별 beat probability 를 가정하며, 임계치 초과 + refractory 30ms 적용.
/// 모델이 없거나 로드 실패 시 자동으로 OnsetBeatDetector 로 fall-back 한다.
final class CoreMLBeatDetector: BeatDetecting {
    private let model: MLModel?
    private let fallback: BeatDetecting
    private let threshold: Double

    init(modelName: String = "BeatDetector", threshold: Double = 0.5, fallback: BeatDetecting = OnsetBeatDetector()) {
        self.threshold = threshold
        self.fallback = fallback
        if let url = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
            self.model = try? MLModel(contentsOf: url)
        } else {
            self.model = nil
        }
    }

    var isModelAvailable: Bool { model != nil }

    func detect(envelope: [Float], sampleRate: Double) -> [BeatEvent] {
        guard let model else {
            return fallback.detect(envelope: envelope, sampleRate: sampleRate)
        }
        // 실제 모델 입출력 shape 은 학습 시 결정됨.
        // 베타에서는 protocol 만 정의하고 fall-back 으로 안전하게 동작.
        // TODO(phase2-coreml): 모델 입출력 spec 확정 후 inference 구현 + 테스트.
        _ = model
        return fallback.detect(envelope: envelope, sampleRate: sampleRate)
    }
}

```

## `WatchAccuracyPro/Core/DSP/DSPPipeline.swift`

```swift
import Accelerate
import Foundation

/// AudioSource 의 샘플 스트림을 받아 envelope·beat 검출·메트릭 분석까지 수행.
///
/// 스레드 분리 (사용자 보고된 freeze 수정):
/// - `process(chunk:)` — AVAudioEngine tap 콜백 스레드. **filter 만 + buffer append + waveform yield**.
///   analyze() 절대 호출 안 함 (autocorrelation 비용이 콜백 budget 초과 → audio dropout + 메인 freeze 유발).
/// - `analyzerTask` — 별도 Task. 1초마다 buffer snapshot 떠 와서 analyze() 한 뒤 metrics yield.
final class DSPPipeline {
    // Round 156 (Aoki + Lim 토론): 30s → 60s. 이론 √2× 정밀도 향상.
    // Round 158: 사용자 요청 — drift 영향 시간 줄이려 30s 로 복귀. cross-window 도 빨라짐.
    static let analysisWindowSeconds: Double = 30
    /// 라이브 emit 주기 — analyzer 가 깨어나는 간격.
    static let liveEmitInterval: Double = 1.0
    /// 라이브 analyze 가 사용할 윈도우 (마지막 N초). final stop 분석은 전체 30초.
    /// 사용자 보고된 "BPH 나왔다 안나왔다" 수정: 6초 → 12초로 늘려서 onset count 두 배 → 락 안정화.
    static let liveAnalysisWindowSeconds: Double = 12
    /// Lock memory — 한 번 BPH 락 성공 후 이 시간 동안은 다음 분석 실패해도 이전 결과 유지.
    /// 사용자 보고된 "나왔다 안나왔다" 추가 완화: 5 → 10초.
    /// Round 158: 60s 측정 동안 BPH 한 번 lock 되면 끝까지 유지. 23s 후 사라지는 사용자 보고 해결.
    static let lockMemorySeconds: Double = 60
    static let waveformDownsampleCount = 200

    private let source: AudioSource
    private let nominalBph: Int
    private let liftAngleDegrees: Double?
    private let escapement: Escapement
    private let reliabilityLabel: ReliabilityLabel
    /// Round 170 (tickIQ-style simplified path): true 면 analyze() 가 SimplifiedBeatDetector 사용.
    /// BP → 48kHz envelope → MAD threshold → parabolic interp → median tight-3% IOI.
    private let useSimplified: Bool

    private let preEmphasis = PreEmphasisFilter()
    private let bandPass: BandPassFilter
    private let envelopeExtractor: EnvelopeExtractor
    // Round 158 (Wang 권고): Multi-band envelope fusion — sapphire-back IWC 같은 frequency-dependent
    // attenuation 환경에서 single band 가 죽어도 다른 band 가 살아남음.
    private let multiBandEnvelope: MultiBandEnvelope
    // Round 158 (tickIQ 분석): noise floor 제거 (crest 2.6 → 9.5 모방).
    private let noiseSuppressor: NoiseFloorSuppressor
    /// 사용자 보고된 BPH lock 실패 root cause 해결 (Audit 4 권고):
    /// envelope 대신 spectral flux 로 onset/BPH 검출.
    private let fluxExtractor = SpectralFluxExtractor()
    /// Round 151 (Kim + Müller + Chen 토론): caliber-conditioned matched filter.
    /// Round 37 IWC 35111 mismatch 회피 — escapement+bph 기반 5개 profile dispatch.
    /// `.bypass` 면 no-op (현재 flux 경로 유지). Layer 3 안전망.
    private let matchedFilter: MatchedFilter
    /// Round 151 (Müller Layer 2): A/B guard — 첫 5초 onset count 비교 후 mf 결과 약하면 자동 bypass.
    private var matchedFilterBypassed: Bool = false

    /// Buffers 는 audio 콜백과 analyzer 가 동시 접근 → lock 으로 보호.
    private let bufferLock = NSLock()
    private var rawBuffer: [Float] = []
    private var envelopeBuffer: [Float] = []  // 48kHz, SNR/amplitude 계산용
    private var fluxBuffer: [Float] = []       // 200Hz, BPH/onset 검출용
    private var startTime: Date?

    /// Round 170 (사용자 보고: 시계 정상인데 +8~+12 s/d 일관 bias):
    /// iPhone audio sample clock (~92-130 ppm drift) 과 wall clock 미세 차이 보정.
    /// 첫 chunk 도착 시점 systemUptime + 그 chunk 의 sample 수 기록 →
    /// 마지막 chunk systemUptime 과 비교해 wall vs audio elapsed 비율 = scaleFactor.
    /// preciseRawBph 를 scaleFactor 로 나눠 wall-clock 기준 BPH 환원.
    private var firstChunkUptime: TimeInterval?
    private var firstChunkSamples: Int = 0
    private var lastChunkUptime: TimeInterval = 0
    private var totalAudioSamples: Int = 0

    private var metricsContinuation: AsyncStream<LiveMetrics>.Continuation?
    private var waveformContinuation: AsyncStream<LiveWaveformChunk>.Continuation?
    private var analyzerTask: Task<Void, Never>?
    private(set) var lastSnapshot: MeasurementResult?
    /// Lock memory — 사용자 보고된 "BPH 나왔다 안나왔다" 수정.
    /// 마지막으로 성공한 분석 결과 + 시각. lockMemorySeconds 안에선 이걸 유지 emit.
    private var lastLockedSnapshot: MeasurementResult?
    private var lastLockedAt: Date?
    /// 사용자 요청 (실시간 tic/toc 점): 최근 검출 onset timestamps (측정 시작 기준 seconds).
    ///   visualization 전용 — 알고리즘 자체는 unchanged. 매 analyze() 마다 갱신.
    private var liveOnsetTimes: [Double] = []
    /// Round 132c (사용자 보고: 같은 조건 측정마다 편차 큼):
    /// 측정 내내 신뢰도 가장 높았던 snapshot 기억. 최종 분석 결과 약하면 이걸 사용.
    /// "운 좋은 한 순간" 도 결과에 반영해 사용자 경험 안정화.
    private var bestLockedSnapshot: MeasurementResult?
    /// Round 32 (Min): analyze() 의 마지막 nil return path. UI 진단용.
    private(set) var lastAnalyzeFailReason: String?

    let liveMetricsStream: AsyncStream<LiveMetrics>
    let liveWaveformStream: AsyncStream<LiveWaveformChunk>

    init(
        source: AudioSource,
        nominalBph: Int,
        liftAngleDegrees: Double?,
        escapement: Escapement,
        reliabilityLabel: ReliabilityLabel,
        useSimplified: Bool = true
    ) {
        self.source = source
        self.nominalBph = nominalBph
        self.liftAngleDegrees = liftAngleDegrees
        self.escapement = escapement
        self.reliabilityLabel = reliabilityLabel
        self.useSimplified = useSimplified
        // Round 153 (Kim+Chen+Müller): caliber-adaptive BP + envelope cutoff.
        // 28800 BPH swissLever 는 production default 와 동일 → 회귀 zero.
        let mfProfile = MatchedFilterProfile.resolve(escapement: escapement, bph: nominalBph)
        let bpSpec = BandPassSpec.spec(for: mfProfile, escapement: escapement)
        self.bandPass = BandPassFilter(
            sampleRate: source.sampleRate,
            lowCutoff: bpSpec.lowHz,
            highCutoff: bpSpec.highHz
        )
        self.envelopeExtractor = EnvelopeExtractor(
            sampleRate: source.sampleRate,
            cutoffHz: bpSpec.envCutoffHz
        )
        self.multiBandEnvelope = MultiBandEnvelope(sampleRate: source.sampleRate)
        self.noiseSuppressor = NoiseFloorSuppressor(sampleRate: source.sampleRate)
        self.matchedFilter = MatchedFilter(profile: mfProfile, sampleRate: source.sampleRate)

        var metricsCont: AsyncStream<LiveMetrics>.Continuation!
        self.liveMetricsStream = AsyncStream(bufferingPolicy: .bufferingNewest(8)) { c in metricsCont = c }
        self.metricsContinuation = metricsCont

        var waveCont: AsyncStream<LiveWaveformChunk>.Continuation!
        self.liveWaveformStream = AsyncStream(bufferingPolicy: .bufferingNewest(8)) { c in waveCont = c }
        self.waveformContinuation = waveCont
    }

    func start() throws {
        startTime = Date()
        firstChunkUptime = nil
        firstChunkSamples = 0
        lastChunkUptime = 0
        totalAudioSamples = 0
        bufferLock.lock()
        rawBuffer.removeAll(keepingCapacity: true)
        envelopeBuffer.removeAll(keepingCapacity: true)
        fluxBuffer.removeAll(keepingCapacity: true)
        bufferLock.unlock()
        preEmphasis.reset()
        bandPass.reset()
        envelopeExtractor.reset()
        multiBandEnvelope.reset()
        noiseSuppressor.reset()
        fluxExtractor.reset()
        matchedFilter.reset()
        lastSnapshot = nil
        lastLockedSnapshot = nil
        lastLockedAt = nil
        bestLockedSnapshot = nil

        try source.start { [weak self] samples in
            self?.process(chunk: samples)
        }

        // 별도 Task — 1초마다 깨어나 analyze() 후 metrics 발행. 콜백 스레드와 분리.
        analyzerTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            // Round 153 (Doyoon coaching): rate ring 5 element — closure capture, lock 없이.
            var rateRing: [Double] = []
            // Round 154 (Müller A/B guard): 5초 시점에 mf vs bypass onset count 비교, mismatch 면 bypass.
            var abGuardChecked = false
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.liveEmitInterval * 1_000_000_000))
                if Task.isCancelled { break }
                let elapsed = Date().timeIntervalSince(self.startTime ?? Date())
                // 라이브 분석은 짧은 윈도우 — autocorrelation 비용 통제.
                if var metrics = self.computeLiveMetrics(elapsed: elapsed) {
                    // Round 154 사용자 실측 보고 — coaching 임계 완화.
                    // micContactScore [-60, -20] → [0, 100] (이전 [-50,-20] 너무 strict, 0% 빈발).
                    if let db = metrics.rawRMSDB {
                        let clamped = max(-60.0, min(-20.0, db))
                        metrics.micContactScore = Int(((clamped + 60.0) / 40.0) * 100.0)
                    }
                    // lockStabilityScore: decay 상수 8 → 18 (사용자 환경 stddev 가 흔히 15-30).
                    if let r = metrics.rateSecondsPerDay {
                        rateRing.append(r)
                        if rateRing.count > 5 { rateRing.removeFirst() }
                        if rateRing.count >= 3 {
                            let mean = rateRing.reduce(0, +) / Double(rateRing.count)
                            let variance = rateRing.map { pow($0 - mean, 2) }.reduce(0, +) / Double(rateRing.count)
                            let stddev = sqrt(variance)
                            metrics.rateRollingStdDev = stddev
                            // stddev 0 → 100, 30+ → 낮은 점수 (exponential decay τ=18).
                            let score = Int(100.0 * exp(-stddev / 18.0))
                            metrics.lockStabilityScore = max(0, min(100, score))
                        }
                    } else {
                        rateRing.removeAll(keepingCapacity: true)
                    }
                    // Round 154 (Müller Layer 2): 5초 시점에 1회 A/B guard.
                    // matched filter 의 onset count 가 bypass(=raw bp flux) 대비 70% 미만이면
                    // profile mismatch → 즉시 bypass 전환. Round 37 silent regression 회피.
                    if !abGuardChecked, elapsed >= 5.0, self.matchedFilter.profile != .bypass {
                        abGuardChecked = true
                        await self.evaluateMatchedFilterABGuard()
                    }
                    self.metricsContinuation?.yield(metrics)
                }
            }
        }
    }

    /// Round 154: 현재까지 buffer 위에서 matched filter 경로 vs bypass 경로 onset count 비교.
    /// 70% 미만이면 matchedFilterBypassed=true 설정 → 이후 chunk 부터 bypass.
    private func evaluateMatchedFilterABGuard() async {
        bufferLock.lock()
        let bpSnapshot = Array(rawBuffer.suffix(Int(source.sampleRate * 5)))
        let fluxSnapshot = Array(fluxBuffer.suffix(Int(SpectralFluxExtractor.outputSampleRate * 5)))
        bufferLock.unlock()
        guard !fluxSnapshot.isEmpty, !bpSnapshot.isEmpty else { return }
        // Round 158 (사용자 보고: 106 beats / 480 expected 후 디버그):
        // A/B guard 일시 비활성화. 이전 코드의 `bpOnsets / 240` 산술 오류로 guard 가 절대 발동 안 했고,
        // 그 상태 (matched filter 항상 on) 가 사실상 더 정확한 detection 을 만들었음 (451 beats).
        // 산술 정정 후 guard 가 발동되어 matched filter 가 bypass 되면서 *오히려* detection 약해짐.
        // 올바른 A/B guard premise 는 향후 라운드에서 재설계.
        _ = fluxSnapshot
        _ = bpSnapshot
        return
    }

    func stop() -> MeasurementResult? {
        analyzerTask?.cancel()
        analyzerTask = nil
        source.stop()
        // Round 170 (사용자 보고: 분석 너무 오래 기다림):
        // simplified path 는 single window 분석으로 충분 (tail-trim retry 우회).
        if useSimplified {
            var result = analyze(windowSeconds: Self.analysisWindowSeconds)
            if result == nil, let best = bestLockedSnapshot {
                result = best
                lastAnalyzeFailReason = nil
            }
            if var r = result {
                r.crossWindowRateDelta = nil
                r.reliabilityGrade = ReliabilityGrade.from(
                    confidence: r.confidenceScore,
                    crossWindowDelta: nil,
                    rateSecondsPerDay: r.rateSecondsPerDay
                )
                result = r
            }
            lastSnapshot = result
            metricsContinuation?.finish()
            waveformContinuation?.finish()
            return result
        }
        // Round 170 (팀 토론 옵션 B): tail-trim retry 통과 windows 평균.
        // 4 windows (trim 0/2/5/8) 모두 분석 → 통과한 candidate 들의 mean rate 채택.
        // 통계적 효과: σ → σ/√(N_eff) (겹침으로 N_eff < 4, 보수적 √2 감소). UX 변경 X.
        let trimOptions: [Double] = [0, 2, 5, 8]
        var allCandidates: [MeasurementResult] = []
        var passingCandidates: [MeasurementResult] = []
        for trim in trimOptions {
            let w = Self.analysisWindowSeconds - trim
            guard w >= 15, let candidate = analyze(windowSeconds: w, tailTrimSeconds: trim) else { continue }
            allCandidates.append(candidate)
            let beatErrOK = candidate.beatErrorMs <= 1.5
            let rateUnc: Double = {
                guard let rms = candidate.residualRMSSeconds, candidate.beatCount > 1 else { return .infinity }
                let n = Double(candidate.beatCount)
                let p = 3600.0 / Double(candidate.bph)
                return rms * 12.0.squareRoot() / pow(n, 1.5) / p * 86400.0
            }()
            let rateUncOK = rateUnc <= 2.0
            if beatErrOK && rateUncOK {
                print("✅ window passed (trim=\(trim)s, rate=\(candidate.rateSecondsPerDay)s/d, beatErr=\(candidate.beatErrorMs)ms, rateUnc=±\(rateUnc)s/d)")
                passingCandidates.append(candidate)
            }
        }
        // 통과 windows 가 있으면 평균. 없으면 first attempt 채택 (실패 표시용).
        var result: MeasurementResult? = {
            if passingCandidates.isEmpty {
                return allCandidates.first
            }
            if passingCandidates.count == 1 {
                return passingCandidates[0]
            }
            // 평균 산출: rate / beatError / amplitude 는 mean. confidence/beats 는 best(max).
            // residualRMS 는 variance pooling: σ_combined = mean(rms²)^0.5 / √N_eff.
            let n = Double(passingCandidates.count)
            let meanRate = passingCandidates.reduce(0.0) { $0 + $1.rateSecondsPerDay } / n
            let meanBeatErr = passingCandidates.reduce(0.0) { $0 + $1.beatErrorMs } / n
            let meanSNR = passingCandidates.reduce(0.0) { $0 + $1.snrDB } / n
            let maxConf = passingCandidates.map { $0.confidenceScore }.max() ?? 0
            let maxBeats = passingCandidates.map { $0.beatCount }.max() ?? 0
            let maxDuration = passingCandidates.map { $0.durationSeconds }.max() ?? 0
            // RMS 결합: 평균 분산의 √(N) 감소. (window 상관 가정해 보수적 √2 정도 실효)
            let pooledRMS: Double? = {
                let rmsValues = passingCandidates.compactMap { $0.residualRMSSeconds }
                guard !rmsValues.isEmpty else { return nil }
                let meanSq = rmsValues.reduce(0.0) { $0 + $1 * $1 } / Double(rmsValues.count)
                // N_eff 보수적 추정 — 4 windows 가 같은 30s overlap 이므로 sqrt(2) 만 감소.
                let nEff = max(1.0, Double(rmsValues.count) / 2.0)
                return (meanSq / nEff).squareRoot()
            }()
            print("📊 averaged \(passingCandidates.count) windows: rate=\(meanRate)s/d (was \(passingCandidates.map { $0.rateSecondsPerDay }))")
            // base = 첫 통과 candidate, rate/beatErr/snr/conf/beats/duration/RMS 만 평균값으로 대체.
            var avg = passingCandidates[0]
            avg = MeasurementResult(
                bph: avg.bph,
                rateSecondsPerDay: meanRate,
                beatErrorMs: meanBeatErr,
                amplitudeDegrees: avg.amplitudeDegrees,
                confidenceScore: maxConf,
                durationSeconds: maxDuration,
                snrDB: meanSNR,
                beatCount: maxBeats,
                reliabilityNote: avg.reliabilityNote
            )
            avg.residualRMSSeconds = pooledRMS
            return avg
        }()
        // Round 170 (사용자 보고: 21s 측정 후 결과의 beats=29/32 (duration=4s)):
        // bestLockedSnapshot 이 live cycle (~4s 시점) 의 stale snapshot 으로 final 30s 결과를
        // 덮어쓰는 버그. tail-trim retry 가 이미 best-of-windows 역할 → bestLockedSnapshot 비활성화.
        // 최종 nil 일 때만 fallback 으로 사용.
        if result == nil, let best = bestLockedSnapshot {
            result = best
            lastAnalyzeFailReason = nil
        }
        // Round 158 (tickIQ trust-the-hint final fallback): analyze 와 bestLock 둘 다 nil 이면
        // signal 있는지 진단 후 nominal echo result 합성. 사용자가 결과 카드 보게 함.
        if result == nil {
            bufferLock.lock()
            let envCount = envelopeBuffer.count
            bufferLock.unlock()
            // 최소 5초 buffer 있고 onset 검출 됐다면 nominal echo 합성.
            if envCount > Int(source.sampleRate * 5) {
                let elapsed = Date().timeIntervalSince(startTime ?? Date())
                result = MeasurementResult(
                    bph: nominalBph,
                    rateSecondsPerDay: 0,
                    beatErrorMs: 0,
                    amplitudeDegrees: nil,
                    confidenceScore: 5,  // 매우 낮음 → F-grade
                    durationSeconds: Int(elapsed.rounded()),
                    snrDB: 0,
                    beatCount: 0,
                    reliabilityNote: .generic
                )
                lastAnalyzeFailReason = "synthesized_nominal_echo"
            }
        }
        // Round 170 (사용자 보고: 분석 30s+ hang):
        // cross-window delta 계산이 추가 3× analyzeSubwindow → 분석 시간 4× 증가.
        // delta nil 로 두면 ReliabilityGrade.from 이 windowPenalty=0 으로 처리 — 거의 영향 없음.
        if var r = result {
            r.crossWindowRateDelta = nil
            r.reliabilityGrade = ReliabilityGrade.from(confidence: r.confidenceScore, crossWindowDelta: nil, rateSecondsPerDay: r.rateSecondsPerDay)
            result = r
        }
        lastSnapshot = result
        metricsContinuation?.finish()
        waveformContinuation?.finish()
        return result
    }

    /// Round 152 + Round 156 (Hyemi F5 fix): analysisWindow 60s 에 맞춰 sub-window 도 20s × 3.
    /// 이전 코드는 30s 고정 sub-window 라 60s 윈도우의 절반(앞 30s)이 검증에서 누락됐음.
    /// nil 반환은 데이터 부족 → grade 영향 없음 (fail-soft).
    private func computeCrossWindowDelta() -> Double? {
        let total = Self.analysisWindowSeconds
        let span = total / 3.0
        let ranges = [(0.0, span), (span, span * 2), (span * 2, total)]
        let subRates: [Double] = ranges.compactMap { (start, end) in
            analyzeSubwindow(startSeconds: start, endSeconds: end)?.rateSecondsPerDay
        }
        guard subRates.count == 3 else { return nil }
        return (subRates.max() ?? 0) - (subRates.min() ?? 0)
    }

    /// Sub-window 분석 — analyze(windowSeconds:) 의 변종. 시간 offset 적용.
    private func analyzeSubwindow(startSeconds: Double, endSeconds: Double) -> MeasurementResult? {
        bufferLock.lock()
        let envCount = envelopeBuffer.count
        let totalSeconds = Double(envCount) / source.sampleRate
        guard totalSeconds >= endSeconds else {
            bufferLock.unlock()
            return nil
        }
        let startIdx = Int((totalSeconds - endSeconds) * source.sampleRate)
        let endIdx = Int((totalSeconds - startSeconds) * source.sampleRate)
        guard startIdx >= 0, endIdx <= envCount, endIdx > startIdx else {
            bufferLock.unlock()
            return nil
        }
        let envSlice = Array(envelopeBuffer[startIdx..<endIdx])
        // Flux 도 동일 시간 slice — sampleRate 차이만큼 scaling.
        let fluxRate = SpectralFluxExtractor.outputSampleRate
        let fluxTotalCount = fluxBuffer.count
        let fluxStartIdx = Int((Double(fluxTotalCount) / fluxRate - endSeconds) * fluxRate)
        let fluxEndIdx = Int((Double(fluxTotalCount) / fluxRate - startSeconds) * fluxRate)
        guard fluxStartIdx >= 0, fluxEndIdx <= fluxTotalCount, fluxEndIdx > fluxStartIdx else {
            bufferLock.unlock()
            return nil
        }
        let fluxSlice = Array(fluxBuffer[fluxStartIdx..<fluxEndIdx])
        bufferLock.unlock()

        // 간략 분석 — beat detect + BPH lock + rate 계산만. (amplitude/SNR/grade 등 skip)
        let rawBeats = BeatDetector.detectOnsets(envelope: fluxSlice, sampleRate: fluxRate)
        // Round 156: sub-pulse cluster — main analyze 와 같은 처리.
        let beats = BeatDetector.clusterSubPulses(beats: rawBeats, nominalBph: nominalBph)
        guard let bphEst = BPHEstimator.estimate(
            envelope: fluxSlice, beats: beats, sampleRate: fluxRate, nominalBphHint: nominalBph
        ) else { return nil }
        let refined = BeatDetector.refineTimestamps(beats: beats, envelope: envSlice, envelopeSampleRate: source.sampleRate)
        // 단순 median IOI — sub-window 는 정밀도보다 일관성 게이트.
        let intervals = (1..<refined.count).map { refined[$0].timestampSeconds - refined[$0 - 1].timestampSeconds }
        let expected = 3600.0 / Double(bphEst.bph)
        let valid = intervals.filter { abs($0 - expected) <= expected * 0.10 }
        guard valid.count >= 8 else { return nil }
        let sorted = valid.sorted()
        let medianIOI = sorted[sorted.count / 2]
        let rawBph = 3600.0 / medianIOI
        let rate = RateCalculator.secondsPerDay(measuredBph: rawBph, nominalBph: nominalBph)
        return MeasurementResult(
            bph: bphEst.bph, rateSecondsPerDay: rate, beatErrorMs: 0,
            amplitudeDegrees: nil, confidenceScore: 0,
            durationSeconds: Int(endSeconds - startSeconds),
            snrDB: 0, beatCount: refined.count,
            reliabilityNote: nil
        )
    }

    // MARK: - Audio callback path

    private func process(chunk: [Float]) {
        // Round 170: audio clock drift 보정용 wall-clock anchor 기록.
        let now = ProcessInfo.processInfo.systemUptime
        totalAudioSamples += chunk.count
        if firstChunkUptime == nil {
            firstChunkUptime = now
            firstChunkSamples = chunk.count
        }
        lastChunkUptime = now
        // 1) filter chain (CPU light, runs on audio thread).
        let pre = preEmphasis.process(chunk)
        let bp = bandPass.process(pre)
        // Round 151 (Müller Layer 3): envelopeExtractor 는 bp 그대로 — amplitude 계산은 unfiltered burst 필요.
        // flux 경로만 matched filter (캘리버 conditioned Gabor) 적용 → noise reject + coupling invariance.
        // `.bypass` 또는 runtime A/B guard 발동 시 mf 가 input 그대로 반환 → 기존 동작 회귀 보장.
        let env = envelopeExtractor.process(bp)
        // Round 158: NoiseSuppressor 재활성화 (Grade A 달성한 조합 복원).
        // Accuracy 변동은 다른 source — measurement-to-measurement variance (mic coupling 등 물리 요인).
        let suppressed = noiseSuppressor.process(bp)
        let flux = fluxExtractor.process(suppressed)
        _ = matchedFilter.process(bp)
        _ = multiBandEnvelope.process(chunk)

        // 2) buffer append + ring trim — protected by lock.
        bufferLock.lock()
        rawBuffer.append(contentsOf: chunk)
        envelopeBuffer.append(contentsOf: env)
        fluxBuffer.append(contentsOf: flux)
        let maxSamples = Int(source.sampleRate * Self.analysisWindowSeconds)
        let trimThreshold = (maxSamples * 3) / 2
        if rawBuffer.count > trimThreshold {
            rawBuffer = Array(rawBuffer.suffix(maxSamples))
        }
        if envelopeBuffer.count > trimThreshold {
            envelopeBuffer = Array(envelopeBuffer.suffix(maxSamples))
        }
        // flux 는 200 Hz rate. 30s 윈도우 = 6000 샘플 — 매우 작음.
        let maxFluxSamples = Int(SpectralFluxExtractor.outputSampleRate * Self.analysisWindowSeconds)
        let fluxTrimThreshold = (maxFluxSamples * 3) / 2
        if fluxBuffer.count > fluxTrimThreshold {
            fluxBuffer = Array(fluxBuffer.suffix(maxFluxSamples))
        }
        bufferLock.unlock()

        // 3) waveform yield (cheap, ~10Hz).
        let waveform = Self.downsample(chunk: chunk, target: Self.waveformDownsampleCount)
        let elapsed = Date().timeIntervalSince(startTime ?? Date())
        waveformContinuation?.yield(LiveWaveformChunk(samples: waveform, elapsedSeconds: elapsed))
    }

    // MARK: - Analyzer (background)

    /// 라이브 metrics — buffer snapshot 후 짧은 윈도우로 분석.
    /// 사용자 보고된 "BPH 나왔다 안나왔다" 수정 — lock memory 적용.
    /// 마지막 성공한 결과를 lockMemorySeconds 동안 유지.
    private func computeLiveMetrics(elapsed: Double) -> LiveMetrics? {
        let diagnostic = computeDiagnosticSnapshot()
        if let snapshot = analyze(windowSeconds: Self.liveAnalysisWindowSeconds) {
            // 락 성공 — 메모리 갱신.
            lastLockedSnapshot = snapshot
            lastLockedAt = Date()
            // Round 132c: 측정 내내 최고 신뢰도 snapshot 추적.
            if let best = bestLockedSnapshot {
                if snapshot.confidenceScore > best.confidenceScore {
                    bestLockedSnapshot = snapshot
                }
            } else {
                bestLockedSnapshot = snapshot
            }
            return LiveMetrics(
                bph: snapshot.bph,
                rateSecondsPerDay: snapshot.rateSecondsPerDay,
                beatErrorMs: snapshot.beatErrorMs,
                amplitudeDegrees: snapshot.amplitudeDegrees,
                confidenceScore: snapshot.confidenceScore,
                elapsedSeconds: elapsed,
                snrDB: snapshot.snrDB,
                rawRMSDB: diagnostic.rawRMSDB,
                onsetCount: snapshot.beatCount,
                envelopeDynamicRange: diagnostic.dynamicRange,
                recentOnsetTimes: liveOnsetTimes
            )
        }
        // 락 실패 — 메모리 안에 있으면 retain.
        if let last = lastLockedSnapshot, let lockedAt = lastLockedAt,
           Date().timeIntervalSince(lockedAt) <= Self.lockMemorySeconds {
            return LiveMetrics(
                bph: last.bph,
                rateSecondsPerDay: last.rateSecondsPerDay,
                beatErrorMs: last.beatErrorMs,
                amplitudeDegrees: last.amplitudeDegrees,
                confidenceScore: max(last.confidenceScore - 5, 0),  // confidence 점차 감쇠
                elapsedSeconds: elapsed,
                snrDB: diagnostic.snrDB,
                rawRMSDB: diagnostic.rawRMSDB,
                onsetCount: diagnostic.onsetCount,
                envelopeDynamicRange: diagnostic.dynamicRange,
                lockFailReason: lastAnalyzeFailReason,
                recentOnsetTimes: liveOnsetTimes
            )
        }
        // 메모리도 만료 — 진단만 emit.
        return LiveMetrics(
            bph: nil, rateSecondsPerDay: nil, beatErrorMs: nil, amplitudeDegrees: nil,
            confidenceScore: 0, elapsedSeconds: elapsed,
            snrDB: diagnostic.snrDB,
            rawRMSDB: diagnostic.rawRMSDB,
            onsetCount: diagnostic.onsetCount,
            envelopeDynamicRange: diagnostic.dynamicRange,
            lockFailReason: lastAnalyzeFailReason,
            recentOnsetTimes: liveOnsetTimes.isEmpty ? nil : liveOnsetTimes
        )
    }

    /// 진단 정보 — raw RMS, envelope dynamic range, onset count.
    private func computeDiagnosticSnapshot() -> (snrDB: Double?, rawRMSDB: Double?, onsetCount: Int?, dynamicRange: Double?) {
        bufferLock.lock()
        let win = Int(source.sampleRate * Self.liveAnalysisWindowSeconds)
        let envCopy = Array(envelopeBuffer.suffix(win))
        let rawCopy = Array(rawBuffer.suffix(win))
        bufferLock.unlock()
        guard !envCopy.isEmpty, !rawCopy.isEmpty else {
            return (nil, nil, nil, nil)
        }
        // raw RMS in dBFS — full-scale = 1.0 → 0 dB.
        var rms: Float = 0
        vDSP_rmsqv(rawCopy, 1, &rms, vDSP_Length(rawCopy.count))
        let rawRMSDB = rms > 0 ? 20 * log10(Double(rms)) : -120.0
        // SNR + dynamic range from envelope.
        let snr = Self.estimateSNR(envelope: envCopy, raw: rawCopy)
        let sorted = envCopy.sorted()
        let p10 = sorted[max(0, sorted.count / 10)]
        let p99 = sorted[min(sorted.count - 1, (sorted.count * 99) / 100)]
        let dynamicRange = p10 > 0 ? Double(p99 / p10) : 0
        // onset count (cheap)
        let onsets = BeatDetector.detectOnsets(envelope: envCopy, sampleRate: source.sampleRate).count
        return (snr, rawRMSDB, onsets, dynamicRange)
    }

    /// 분석 — 마지막 `windowSeconds` envelope window 만 사용.
    /// 호출자가 analyzer Task 또는 stop() 한 곳뿐이라 audio 콜백 스레드와 무관.
    func analyze() -> MeasurementResult? {
        analyze(windowSeconds: Self.analysisWindowSeconds)
    }

    func analyze(windowSeconds: Double) -> MeasurementResult? {
        // Round 170 (팀 재토론, 사용자 실측: template on 시 mean -27 σ 22 — 악화):
        // template 이 다중 peak envelope (main + ring) 에서 잘못된 feature 학습 → systematic shift.
        // 비활성화 유지. 1% IOI 필터만으로 mean -4 σ 5 달성 (이전 베스트).
        if useSimplified {
            return analyzeSimplified(windowSeconds: windowSeconds, tailTrimSeconds: 0)
        }
        return analyzeInternal(windowSeconds: windowSeconds, tailTrimSeconds: 0, useTemplate: false)
    }

    /// Round 170: 측정 마지막 N초 가 corrupted 일 때 tail trim 후 분석.
    func analyze(windowSeconds: Double, tailTrimSeconds: Double) -> MeasurementResult? {
        if useSimplified {
            return analyzeSimplified(windowSeconds: windowSeconds, tailTrimSeconds: tailTrimSeconds)
        }
        return analyzeInternal(windowSeconds: windowSeconds, tailTrimSeconds: tailTrimSeconds, useTemplate: false)
    }

    /// Round 170 (tickIQ-style simplified DSP) — v3:
    /// 사용자 보고: envelope median-IOI 방식이 +140-160 s/d systematic bias.
    /// 원인 — envelope local-max detection 자체의 phase shift (BP/LPF 위상 응답 + asymmetric peak shape).
    /// 해결: **autocorrelation 기반 period 산출** — bias 없는 unbiased estimator.
    /// Flow: flux signal (200Hz, 기존 fluxBuffer) → FFT autocorrelation → peak lag = period → BPH.
    /// onset 검출은 beatErrorMs/beatCount/confidence 표시용으로만 유지 (rate 계산엔 영향 X).
    private func analyzeSimplified(windowSeconds: Double, tailTrimSeconds: Double) -> MeasurementResult? {
        let analyzeStart = ProcessInfo.processInfo.systemUptime
        defer {
            let analyzeElapsed = (ProcessInfo.processInfo.systemUptime - analyzeStart) * 1000
            print("⏱️ analyzeSimplified(win=\(windowSeconds)s, trim=\(tailTrimSeconds)s): \(String(format: "%.0f", analyzeElapsed))ms")
        }

        // 1) Snapshot flux + envelope + raw + window slice.
        bufferLock.lock()
        let envCount = envelopeBuffer.count
        let rawCount = rawBuffer.count
        let fluxRate = SpectralFluxExtractor.outputSampleRate
        guard envCount > Int(source.sampleRate * 0.5) else {
            bufferLock.unlock()
            lastAnalyzeFailReason = "buffer<0.5s(simplified)"
            return nil
        }
        let tailTrimEnv = Int(tailTrimSeconds * source.sampleRate)
        let envEndIdx = max(0, envCount - tailTrimEnv)
        let target = Int(source.sampleRate * windowSeconds)
        let envStartIdx = max(0, envEndIdx - target)
        let envSlice: [Float] = (envEndIdx > envStartIdx)
            ? Array(envelopeBuffer[envStartIdx..<envEndIdx]) : []
        let rawEndIdx = max(0, rawCount - tailTrimEnv)
        let rawStartIdx = max(0, rawEndIdx - target)
        let rawSlice: [Float] = (rawEndIdx > rawStartIdx)
            ? Array(rawBuffer[rawStartIdx..<rawEndIdx]) : []
        // Flux snapshot (same window in time).
        let tailTrimFlux = Int(tailTrimSeconds * fluxRate)
        let fluxEndIdx = max(0, fluxBuffer.count - tailTrimFlux)
        let fluxTarget = Int(fluxRate * windowSeconds)
        let fluxStartIdx = max(0, fluxEndIdx - fluxTarget)
        let fluxSlice: [Float] = (fluxEndIdx > fluxStartIdx)
            ? Array(fluxBuffer[fluxStartIdx..<fluxEndIdx]) : []
        bufferLock.unlock()

        guard envSlice.count > Int(source.sampleRate * 0.5) else {
            lastAnalyzeFailReason = "trimmed<0.5s(simplified)"
            return nil
        }
        guard fluxSlice.count > Int(fluxRate * 2) else {
            lastAnalyzeFailReason = "flux<2s(simplified)"
            return nil
        }

        // 2) Onset 검출 (flux 위) — 추후 beatError/confidence 표시용. Rate 계산엔 영향 X.
        let coarseBeats = BeatDetector.detectOnsets(envelope: fluxSlice, sampleRate: fluxRate)
        guard coarseBeats.count >= 8 else {
            lastAnalyzeFailReason = "onsets<8(simplified, got=\(coarseBeats.count))"
            return nil
        }

        // 3) BPHEstimator (autocorrelation) — rawBph 가 bias 없는 period 추정.
        // legacy path 도 autocorrelation 사용 → 검증된 unbiased estimator.
        guard let bphEst = BPHEstimator.estimate(
            envelope: fluxSlice,
            beats: coarseBeats,
            sampleRate: fluxRate,
            nominalBphHint: nominalBph
        ) else {
            lastAnalyzeFailReason = "bph_lock_fail(simplified)"
            return nil
        }
        guard bphEst.bph > 0 else {
            lastAnalyzeFailReason = "bph=0(simplified)"
            return nil
        }

        // 4) 48kHz envelope 위에서 onset timestamps refine — beatError 표시용 (rate 계산엔 사용 X).
        let refined = BeatDetector.refineTimestamps(
            beats: coarseBeats,
            envelope: envSlice,
            envelopeSampleRate: source.sampleRate
        )
        let onsets: [Double] = refined.map { $0.timestampSeconds }
        // 사용자 요청 (실시간 tic/toc 점): cumulative append + **measurement-start 기준 timestamp**.
        //   onset.timestampSeconds 는 envSlice 안 offset → envSlice 시작 시각을 더해 절대 시점으로 변환.
        //   envSliceStartTime = envStartIdx / sampleRate (measurement start 기준).
        let envSliceStartTime = Double(envStartIdx) / source.sampleRate
        let absoluteOnsets = onsets.map { $0 + envSliceStartTime }
        let lastSeen = liveOnsetTimes.last ?? -Double.infinity
        let fresh = absoluteOnsets.filter { $0 > lastSeen + 0.001 }
        if !fresh.isEmpty {
            liveOnsetTimes.append(contentsOf: fresh)
            if liveOnsetTimes.count > 200 {
                liveOnsetTimes.removeFirst(liveOnsetTimes.count - 200)
            }
        }

        // 5) Rate = autocorrelation rawBph 기반 (unbiased).
        let rate = RateCalculator.secondsPerDay(measuredBph: bphEst.rawBph, nominalBph: nominalBph)

        // 5) Sanity guards (기존 path 와 동일).
        guard abs(rate) <= 300 else {
            lastAnalyzeFailReason = "rate>300(simplified, \(Int(rate)))"
            return nil
        }

        // 6) Beat error — 인접 IOI 변동 평균. Sub-pulse 가 있다면 alternating pattern.
        // tight IOIs 의 인접 차이 절반 → 박동오차 ms (단순 근사, OLS path 와 비교 가능).
        let nominalIOI = 3600.0 / Double(nominalBph)
        let tolerance = nominalIOI * 0.03
        var iois: [Double] = []
        for i in 1..<onsets.count {
            let d = onsets[i] - onsets[i-1]
            if abs(d - nominalIOI) <= tolerance {
                iois.append(d)
            }
        }
        let beatErrorMs: Double = {
            guard iois.count >= 4 else { return 0 }
            // alternating short-long pattern 의 진폭 → beat error.
            var deltas: [Double] = []
            for i in 1..<iois.count {
                deltas.append(abs(iois[i] - iois[i-1]))
            }
            let sorted = deltas.sorted()
            let medianDelta = sorted[sorted.count / 2]
            return medianDelta * 1000.0 / 2.0  // ms, half-amplitude.
        }()

        // 6) Residual RMS — tight IOI 들의 평균 대비 표준편차. rate 정밀도 표시용.
        let residualRMS: Double? = {
            guard iois.count >= 4 else { return nil }
            let mean = iois.reduce(0, +) / Double(iois.count)
            let variance = iois.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(iois.count)
            return variance.squareRoot()
        }()

        // 7) SNR (재사용).
        let snr = Self.estimateSNR(envelope: envSlice, raw: rawSlice)

        // 8) Amplitude — 기존 AmplitudeEstimator 재사용. high-reliability 만.
        let beatEvents: [BeatEvent] = refined
        let amplitude: Double? = {
            guard reliabilityLabel.displaysAmplitude else { return nil }
            return AmplitudeEstimator.estimate(
                envelope: envSlice,
                beats: beatEvents,
                sampleRate: source.sampleRate,
                liftAngleDegrees: liftAngleDegrees,
                escapement: escapement
            )
        }()

        // 9) Confidence — onsets 개수 + RMS + SNR 기반.
        let confidence: Int = {
            let tightRatio = Double(iois.count) / Double(max(1, onsets.count - 1))
            var score = 60.0
            if tightRatio >= 0.7 { score += 20 } else if tightRatio >= 0.5 { score += 10 }
            let rms = residualRMS ?? 0.001
            if rms < 0.0002 { score += 10 } else if rms < 0.0005 { score += 5 }
            if snr > 15 { score += 5 }
            return max(0, min(100, Int(score)))
        }()

        let elapsed = Date().timeIntervalSince(startTime ?? Date())
        let reliabilityNote: ReliabilityNote? = {
            switch reliabilityLabel {
            case .medium, .low, .unverified: return .generic
            case .high, .veryHigh:           return nil
            }
        }()

        lastAnalyzeFailReason = nil
        var result = MeasurementResult(
            bph: bphEst.bph,
            rateSecondsPerDay: rate,
            beatErrorMs: beatErrorMs,
            amplitudeDegrees: amplitude,
            confidenceScore: confidence,
            durationSeconds: Int(elapsed.rounded()),
            snrDB: snr,
            beatCount: onsets.count,
            reliabilityNote: reliabilityNote
        )
        result.residualRMSSeconds = residualRMS
        print("📈 simplified rate=\(String(format: "%.2f", rate)) rawBph=\(String(format: "%.3f", bphEst.rawBph)) bph=\(bphEst.bph) onsets=\(onsets.count) tight=\(iois.count) RMS=\(residualRMS.map { String(format: "%.0fμs", $0 * 1e6) } ?? "—") conf=\(confidence)")
        return result
    }

    private func analyzeInternal(windowSeconds: Double, tailTrimSeconds: Double, useTemplate: Bool) -> MeasurementResult? {
        // Round 170 (Sora monitoring): 분석 시간 로깅. 200ms 초과 시 template 추가 축소 필요.
        let analyzeStart = ProcessInfo.processInfo.systemUptime
        defer {
            let analyzeElapsed = (ProcessInfo.processInfo.systemUptime - analyzeStart) * 1000
            if useTemplate {
                print("⏱️ analyze(win=\(windowSeconds)s, trim=\(tailTrimSeconds)s, tmpl=on): \(String(format: "%.0f", analyzeElapsed))ms")
            }
        }
        // snapshot 떠 오기 — lock 안에서 빠르게 copy.
        // Round 170: tailTrimSeconds 만큼 end 에서 제거 후 last N seconds 분석.
        bufferLock.lock()
        let envCount = envelopeBuffer.count
        guard envCount > Int(source.sampleRate * 0.5) else {
            bufferLock.unlock()
            lastAnalyzeFailReason = "buffer<0.5s"
            return nil
        }
        let tailTrimEnv = Int(tailTrimSeconds * source.sampleRate)
        let envEndIdx = max(0, envCount - tailTrimEnv)
        let target = Int(source.sampleRate * windowSeconds)
        let envStartIdx = max(0, envEndIdx - target)
        let analyzeBuffer: [Float] = (envEndIdx > envStartIdx)
            ? Array(envelopeBuffer[envStartIdx..<envEndIdx]) : []
        let rawEndIdx = max(0, rawBuffer.count - tailTrimEnv)
        let rawStartIdx = max(0, rawEndIdx - target)
        let rawSnapshot: [Float] = (rawEndIdx > rawStartIdx)
            ? Array(rawBuffer[rawStartIdx..<rawEndIdx]) : []
        // Flux snapshot — 200 Hz transient signal, BPH/onset 검출 전용.
        let fluxRate = SpectralFluxExtractor.outputSampleRate
        let tailTrimFlux = Int(tailTrimSeconds * fluxRate)
        let fluxEndIdx = max(0, fluxBuffer.count - tailTrimFlux)
        let fluxTarget = Int(fluxRate * windowSeconds)
        let fluxStartIdx = max(0, fluxEndIdx - fluxTarget)
        let fluxSnapshot: [Float] = (fluxEndIdx > fluxStartIdx)
            ? Array(fluxBuffer[fluxStartIdx..<fluxEndIdx]) : []
        bufferLock.unlock()
        guard analyzeBuffer.count > Int(source.sampleRate * 0.5) else {
            lastAnalyzeFailReason = "trimmed<0.5s"
            return nil
        }

        // Round 37: NoiseSuppressor 도 revert (정상 tic burst zero out 위험).
        // tickIQ 는 marginal 신호도 측정. 우리는 너무 strict → revert.
        let rawOnsets = BeatDetector.detectOnsets(envelope: fluxSnapshot, sampleRate: fluxRate)
        // Round 158 (사용자 보고: 측정 간 ±30 s/d swing):
        // BandPass 6-15kHz + NoiseSuppressor 가 이미 sub-pulse 분리 충분.
        // Cluster 가 측정마다 다른 stage 선택해 centroid drift 야기 가능 → 비활성화.
        let coarseBeats = rawOnsets
        // Round 158 (envelope autocorrelation fallback): flux 자가상관 실패 시 envelope 시간 도메인 자가상관.
        // envelope 은 burst-baseline bimodal — flux 가 약해도 envelope 의 주기 살아남음. IWC sapphire-back 대응.
        // 48kHz envelope 을 200Hz 로 downsample (240-sample max pooling) → flux 와 같은 rate.
        let envFluxRate = fluxRate
        var envelopeDownsampled: [Float] = []
        let hop = max(1, Int(source.sampleRate / envFluxRate))
        envelopeDownsampled.reserveCapacity(analyzeBuffer.count / hop)
        var idx = 0
        while idx + hop <= analyzeBuffer.count {
            var localMax: Float = 0
            for j in idx..<(idx + hop) where analyzeBuffer[j] > localMax { localMax = analyzeBuffer[j] }
            envelopeDownsampled.append(localMax)
            idx += hop
        }
        let envOnsets = BeatDetector.detectOnsets(envelope: envelopeDownsampled, sampleRate: envFluxRate)
        // Round 158: cluster 비활성화 — envelope path 도 동일하게.
        let envCoarseBeats = envOnsets
        let envBphEstimate = BPHEstimator.estimate(
            envelope: envelopeDownsampled,
            beats: envCoarseBeats,
            sampleRate: envFluxRate,
            nominalBphHint: nominalBph
        )
        // 표준 path 우선, 실패 시 envelope path fallback.
        let standardBphEstimate = BPHEstimator.estimate(
            envelope: fluxSnapshot,
            beats: coarseBeats,
            sampleRate: fluxRate,
            nominalBphHint: nominalBph
        )
        // Round 158 (tickIQ trust-the-hint): BPHEstimator 둘 다 실패해도 *signal 있으면* nominal echo 반환.
        // 사용자가 watch 등록한 BPH 신뢰. 결과 카드 항상 표시 (F-grade) — tickIQ 와 동일 UX 패턴.
        // 진짜 lock 실패 (no signal) 만 nil 반환.
        let bphEstimate: BPHEstimate = {
            if let est = standardBphEstimate ?? envBphEstimate { return est }
            // Fallback: nominalBph echo with minimal confidence.
            // 안전 가드: 최소 8 onset 있어야 (완전 무신호 차단).
            if max(coarseBeats.count, envCoarseBeats.count) >= 8 {
                lastAnalyzeFailReason = "fallback_nominal_echo(flux=\(coarseBeats.count) env=\(envCoarseBeats.count))"
                return BPHEstimate(
                    bph: nominalBph,
                    rawBph: Double(nominalBph),
                    confidence: 0.005,  // 매우 낮음 → F-grade 보장
                    peakLagSeconds: 3600.0 / Double(nominalBph)
                )
            }
            // 신호 자체 없음 — 진짜 실패.
            lastAnalyzeFailReason = "no_signal(flux=\(coarseBeats.count) env=\(envCoarseBeats.count))"
            return BPHEstimate(bph: 0, rawBph: 0, confidence: 0, peakLagSeconds: 0)
        }()
        guard bphEstimate.bph > 0 else { return nil }
        // 만약 envelope path 가 lock 잡았으면 그 beats 를 후속 분석에 사용.
        let actualBeats = standardBphEstimate != nil ? coarseBeats : envCoarseBeats
        let elapsed = Date().timeIntervalSince(startTime ?? Date())
        // Round 132 FIX (사용자: rate +122 / -59.1 / 측정마다 180s/d swing):
        // 원인 — 200Hz flux 위 autocorr → 28800 BPH lag=25 samples, 1 sample=4% 변동=±180 s/d swing.
        // 해법 — BPH lock 은 flux 기반 그대로 (28800 정확), **rate 만** refined timestamps
        // (48kHz envelope parabolic interp 으로 ~0.02ms 정밀도) IOI median 으로 별도 계산.
        let beats: [BeatEvent] = {
            // Round 158 (PLL + Template 통합): 측정 정확도 fundamental 향상.
            // 1) refineTimestamps 로 envelope peak 정밀도 부여.
            // 2) PLL 로 outlier (sub-pulse, noise) 제거 + period 안정 추적.
            // 3) Template matching 으로 sub-millisecond 시간 정밀도.
            let refined = BeatDetector.refineTimestamps(
                beats: actualBeats,
                envelope: analyzeBuffer,
                envelopeSampleRate: source.sampleRate
            )
            guard refined.count >= 16 else { return refined }
            // PLL bootstrap — initial period from first 10-15 beats median IOI.
            let bootstrapBeats = Array(refined.prefix(15))
            let bootstrapIOIs = (1..<bootstrapBeats.count).map {
                bootstrapBeats[$0].timestampSeconds - bootstrapBeats[$0 - 1].timestampSeconds
            }
            let nominalPeriod = 3600.0 / Double(bphEstimate.bph)
            // Filter bootstrap IOIs to ±10% of nominal — clean initial period.
            let cleanIOIs = bootstrapIOIs.filter { abs($0 - nominalPeriod) <= nominalPeriod * 0.10 }
            let initialPeriod = cleanIOIs.count >= 4 ? cleanIOIs.sorted()[cleanIOIs.count / 2] : nominalPeriod
            let pll = PLLTracker(initialPeriod: initialPeriod)
            pll.bootstrap(firstOnset: refined[0].timestampSeconds)
            // PLL-locked beats — only those that match phase prediction.
            var lockedBeats: [BeatEvent] = [refined[0]]
            for beat in refined.dropFirst() {
                if pll.tryLock(onsetTime: beat.timestampSeconds) {
                    lockedBeats.append(beat)
                }
            }
            guard lockedBeats.count >= 16 else { return refined }
            // Round 170: template refinement 은 final 분석 (windowSeconds≥20) 에만.
            // live cycle 마다 돌리면 analyzer task 가 budget 초과 → metrics 정지.
            guard useTemplate else { return lockedBeats }
            // Round 170 (사용자 보고: 분석 너무 오래): template window/search 절반 → 4× 빠름.
            // 4ms 도 충분 (PLL 이 phase 를 이미 잡았고 template 은 sub-sample fine refine 만).
            let templateMatcher = TemplateMatcher(sampleRate: source.sampleRate, halfWindowMs: 4)
            templateMatcher.learn(envelope: analyzeBuffer, onsets: Array(lockedBeats.prefix(10)))
            guard !templateMatcher.template.isEmpty else { return lockedBeats }
            // Template-refined timestamps — sub-millisecond precision.
            let templateRefined: [BeatEvent] = lockedBeats.map { beat in
                let preciseTime = templateMatcher.refinePeakTime(
                    envelope: analyzeBuffer,
                    expectedTime: beat.timestampSeconds,
                    searchWindowMs: 4
                )
                return BeatEvent(
                    timestampSeconds: preciseTime,
                    type: beat.type,
                    energy: beat.energy
                )
            }
            return templateRefined
        }()
        // Round 150 (Müller H1): Phase-locked linear regression + RANSAC.
        // 기존 median-IOI 는 인접 beat 1쌍의 정보만 사용 → 30s × 240 beats 중 1쌍의 IOI 채택.
        // 해법: 누적 phase residual — beat index → timestamp 의 OLS slope 가 period.
        // RANSAC outlier 제거 + R² 검증으로 ±50 → ±3 s/d 정밀도 향상 가능 (이론적 √N ≈ 15× leverage).
        // Round 170 (사용자 통찰 + 요청: "박동오차 1ms 이하 데이터만 써야"):
        // sub-pulse 혼동 (tic 의 main + secondary ring 번갈아 잡힘) beat 제거.
        // surrounding IOI 가 nominal period 의 정수배 (±5%) 가 아닌 beat 는 OLS + beat error 둘 다에서 제외.
        // 누락된 beat 인접 (IOI = 2× nominal) 도 통과 → leverage 보존.
        let nominalPeriodForFilter = 3600.0 / Double(bphEstimate.bph)
        let cleanedBeats: [BeatEvent] = {
            let warmBeats = beats.filter { $0.timestampSeconds >= 2.0 }
            let candidate = warmBeats.count >= 30 ? warmBeats : beats
            guard candidate.count >= 5 else { return candidate }
            // Round 170 (사용자 측정 6번 데이터: 박동오차 5-11ms 가 50% — sub-pulse 혼동):
            // tolerance 5% (±6.25ms) → 1% (±1.25ms) 강화. sub-pulse 인 beat 자동 제외.
            // 누락 인접 (2×, 3× IOI) 은 그대로 통과.
            let tolerance = 0.01
            return (0..<candidate.count).compactMap { i in
                let inIOI: Double = i > 0
                    ? candidate[i].timestampSeconds - candidate[i-1].timestampSeconds
                    : nominalPeriodForFilter
                let outIOI: Double = i < candidate.count - 1
                    ? candidate[i+1].timestampSeconds - candidate[i].timestampSeconds
                    : nominalPeriodForFilter
                func ioiOK(_ ioi: Double) -> Bool {
                    let normalized = ioi / nominalPeriodForFilter
                    let nearest = round(normalized)
                    return nearest >= 1 && nearest <= 5 && abs(normalized - nearest) <= tolerance
                }
                return (ioiOK(inIOI) && ioiOK(outIOI)) ? candidate[i] : nil
            }
        }()

        // Round 170 (사용자 보고: 시계 정상인데 -17~-38 s/d 일관 음수 bias):
        // OLS 는 ALL beats 평균 → 시스템 bias 그대로 반영.
        // Trimmed mean 접근: consecutive IOI 정렬 → 상하위 25% 제거 → 중간 50% 평균.
        // - Outlier (sub-pulse 일부): 양 끝에 모임 → 자동 제거
        // - 교대 sub-pulse (절반 짧고 절반 김): 중간 50% 에 양쪽 섞임 → 평균이 진짜 period
        // - Systematic shift (전부 일정 shift): 그대로 통과 (OLS 와 동일 결과 → 채택 안 됨)
        let trimmedMeanBph: Double? = {
            guard cleanedBeats.count >= 16 else { return nil }
            var ones: [Double] = []
            for i in 1..<cleanedBeats.count {
                let ioi = cleanedBeats[i].timestampSeconds - cleanedBeats[i-1].timestampSeconds
                let n = ioi / nominalPeriodForFilter
                if abs(n - 1.0) <= 0.03 { ones.append(ioi) }  // ±3% 까지 허용해 sub-pulse 도 일부 포함
            }
            guard ones.count >= 16 else { return nil }
            let sorted = ones.sorted()
            let trimCount = sorted.count / 4
            let middle = Array(sorted[trimCount..<(sorted.count - trimCount)])
            guard !middle.isEmpty else { return nil }
            let avg = middle.reduce(0, +) / Double(middle.count)
            return 3600.0 / avg
        }()

        // OLS 와 비교 후 채택.
        let (preciseRawBph, residualRMS): (Double, Double?) = {
            guard cleanedBeats.count >= 30 else {
                return (fallbackMedianRawBph(beats: beats, bphEstimate: bphEstimate), nil)
            }
            let nominalPeriod = nominalPeriodForFilter
            let (slope, residuals) = ordinaryLeastSquaresPeriod(usable: cleanedBeats, nominalPeriod: nominalPeriod)
            guard let slope, !residuals.isEmpty else {
                return (fallbackMedianRawBph(beats: beats, bphEstimate: bphEstimate), nil)
            }
            // 2) RANSAC: drop |residual| > 2 × MAD, refit. 5회 반복. cap 1ms.
            var currentBeats = cleanedBeats
            var currentSlope = slope
            var currentResiduals = residuals
            for _ in 0..<5 {
                let mad = Self.medianAbsoluteDeviation(of: currentResiduals)
                let threshold = min(0.001, max(0.0002, 2.0 * mad))
                let filtered = zip(currentBeats, currentResiduals).compactMap { (b, r) in
                    abs(r) <= threshold ? b : nil
                }
                guard filtered.count >= Int(Double(currentBeats.count) * 0.7),
                      filtered.count >= 30 else { break }
                let (newSlope, newResiduals) = ordinaryLeastSquaresPeriod(usable: filtered, nominalPeriod: nominalPeriod)
                guard let newSlope, !newResiduals.isEmpty else { break }
                currentBeats = filtered
                currentSlope = newSlope
                currentResiduals = newResiduals
            }
            // residual RMS — rate 정밀도 직접 metric (R² 와 무관하게 항상 계산).
            let sumSq = currentResiduals.reduce(0.0) { $0 + $1 * $1 }
            let rms: Double? = (currentResiduals.count > 0) ? (sumSq / Double(currentResiduals.count)).squareRoot() : nil
            // 3) R² 검증 — 너무 noisy 면 fallback (단 RMS 는 보존해 게이트가 nil 로 무력화되지 않도록).
            let r2 = Self.coefficientOfDetermination(beats: currentBeats, slope: currentSlope)
            guard r2 >= 0.999 else {
                return (fallbackMedianRawBph(beats: beats, bphEstimate: bphEstimate), rms)
            }
            return (3600.0 / currentSlope, rms)
        }()
        // Round 170: OLS vs Trimmed mean cross-check.
        // 차이 > 5 s/d → trimmed mean 채택 (OLS bias 의심, outlier/sub-pulse 영향 vs 강건).
        let finalRawBph: Double = {
            guard let tm = trimmedMeanBph else { return preciseRawBph }
            let olsRate = (preciseRawBph - Double(nominalBph)) / Double(nominalBph) * 86400.0
            let tmRate = (tm - Double(nominalBph)) / Double(nominalBph) * 86400.0
            let diff = abs(olsRate - tmRate)
            if diff > 5.0 {
                print("📊 OLS vs TrimmedMean 차이 \(String(format: "%.1f", diff)) s/d — TM 채택 (OLS rate=\(String(format: "%.1f", olsRate)), TM rate=\(String(format: "%.1f", tmRate)))")
                return tm
            }
            return preciseRawBph
        }()
        // Round 132b: cross-window consistency check 는 보류 — 사용자 보고 lock 실패 3연속,
        // 현재 시점에선 추가 게이트 위험. 우선 안정성 확보 후 재도입.
        // Round 41 fix: drift > 3% → measured 채택 logic 제거. 항상 nominalBph 사용.
        // 사용자 보고: Omega 8800 (25200 BPH) 인데 algorithm 이 28800 lock → rate -4064 광기.
        // nominalForRate 가 measured 28800 채택해 거대 rate. 항상 nominal 사용하면 잘못된 lock 즉시 reject.
        let nominalForRate = nominalBph
        // Round 170 (사용자 보고: calibration 적용 시 +bias 가 오히려 커짐):
        // +bias 의 원인이 audio clock drift 가 아니라 detection feature 위치 (예: tic envelope peak
        // 이 진짜 impact 보다 일정 시간 지연돼 누적) 일 수 있음. clock-drift 보정은 반대 방향으로
        // 작용해 악화. 일단 보정 비활성화 — diagnostic 정보만 수집.
        let measuredPPM: Double = {
            guard let first = firstChunkUptime,
                  totalAudioSamples > firstChunkSamples,
                  lastChunkUptime > first else { return 0 }
            let wallElapsed = lastChunkUptime - first
            let audioElapsed = Double(totalAudioSamples - firstChunkSamples) / source.sampleRate
            guard audioElapsed > 5.0, wallElapsed > 5.0 else { return 0 }
            return (wallElapsed / audioElapsed - 1.0) * 1e6
        }()
        let rate = RateCalculator.secondsPerDay(measuredBph: finalRawBph, nominalBph: nominalForRate)
        print("🕐 measured ppm=\(String(format: "%.1f", measuredPPM)) finalRawBph=\(String(format: "%.3f", finalRawBph)) (OLS=\(String(format: "%.3f", preciseRawBph)), TM=\(trimmedMeanBph.map { String(format: "%.3f", $0) } ?? "nil")) rate=\(String(format: "%.2f", rate))")
        // Round 170 (팀 토론): beat error 도 cleanedBeats (IOI-filtered) 에서 계산 →
        // 표시 metric ↔ rate 계산 데이터 출처 일치. PLL beats 의 sub-pulse 인공 잡음 제거됨.
        let beatErrorMs = BeatErrorCalculator.beatErrorMs(beats: cleanedBeats.count >= 5 ? cleanedBeats : beats) ?? 0
        let snr = Self.estimateSNR(envelope: analyzeBuffer, raw: rawSnapshot)

        let amplitude: Double? = {
            guard reliabilityLabel.displaysAmplitude else { return nil }
            return AmplitudeEstimator.estimate(
                envelope: analyzeBuffer,
                beats: beats,
                sampleRate: source.sampleRate,
                liftAngleDegrees: liftAngleDegrees,
                escapement: escapement
            )
        }()

        // sanity guard — 광기 차단.
        // rate ±300 s/d 내, beat error 100 ms 이내 (persist guard 와 일치).
        // Round 30: 30ms guard 가 BPH lock 자체를 차단하는 버그였음. missing tic 으로 IOI 부풀려진
        // case (사용자 보고: 70 onsets/12s 인데도 BPH —) 에서 lock 잡힘 차단. 100ms 로 완화 + UI 에서 처리.
        guard abs(rate) <= 300 else {
            lastAnalyzeFailReason = "rate>300(\(Int(rate)))"
            return nil
        }
        guard beatErrorMs <= 100 else {
            lastAnalyzeFailReason = "beatErr>100(\(Int(beatErrorMs)))"
            return nil
        }

        let confidence = ConfidenceScorer.score(.init(
            snrDB: snr,
            durationSeconds: elapsed,
            bphAutocorrelationConfidence: bphEstimate.confidence,
            beatCount: beats.count,
            beatErrorMs: beatErrorMs
        ))

        // Round 170: amplitude cell 자체를 UI 에서 제거 → amplitude 관련 안내 카드(coaxial / amplitudeUnstable)
        // 도 일관성 위해 비활성화. medium/low 캘리버의 측정 정확도 안내(generic) 만 유지.
        let reliabilityNote: ReliabilityNote? = {
            switch reliabilityLabel {
            case .medium, .low, .unverified:
                return .generic
            case .high, .veryHigh:
                return nil
            }
        }()

        lastAnalyzeFailReason = nil  // success
        var result = MeasurementResult(
            bph: bphEstimate.bph,
            rateSecondsPerDay: rate,
            beatErrorMs: beatErrorMs,
            amplitudeDegrees: amplitude,
            confidenceScore: confidence,
            durationSeconds: Int(elapsed.rounded()),
            snrDB: snr,
            beatCount: beats.count,
            reliabilityNote: reliabilityNote
        )
        result.residualRMSSeconds = residualRMS
        return result
    }

    // MARK: - SNR / utilities

    /// 라이브 emit 시점에 buffer snapshot 떠서 SNR 만 계산 (BPH 분석 못할 때 fallback).
    private func computeSNRSnapshot() -> Double? {
        bufferLock.lock()
        let env = envelopeBuffer.suffix(Int(source.sampleRate * Self.liveAnalysisWindowSeconds))
        let raw = rawBuffer.suffix(Int(source.sampleRate * Self.liveAnalysisWindowSeconds))
        let envCopy = Array(env)
        let rawCopy = Array(raw)
        bufferLock.unlock()
        guard !envCopy.isEmpty else { return nil }
        return Self.estimateSNR(envelope: envCopy, raw: rawCopy)
    }

    // Round 150 (Müller H1): Phase-locked linear regression helpers.
    // beat index → timestamp 의 OLS slope = period (rate 정밀도의 √N leverage).

    /// OLS fit: timestamp_i = slope · i + intercept. residuals = observed - predicted.
    /// nominalPeriod 은 numerical conditioning + initial centering 용도 (timestamp 가 큰 절대값일 때 정밀도 보존).
    /// Round 170 (사용자 요구: ±1 s/d 정밀):
    /// 비트가 일부 누락돼도 정확한 slope 산출하도록 **실제 beat 인덱스**를 nominal period 로 추정.
    /// 이전 코드는 sequential 0,1,2..N — 96/240 검출 시 slope 가 2.5× nominal 로 잘못 계산되어
    /// drift check 에서 거부 → 약한 median fallback 으로 떨어져 정밀도 ±10-50 s/d.
    /// 새 코드는 ti 의 expected_index = round((ti - t0) / nominalPeriod) — 누락 자동 보정.
    /// 결과: 96/240 검출만으로도 √96 ≈ 10× leverage 로 ±2 s/d 가능.
    private func ordinaryLeastSquaresPeriod(usable: [BeatEvent], nominalPeriod: Double) -> (slope: Double?, residuals: [Double]) {
        let n = Double(usable.count)
        guard n >= 2 else { return (nil, []) }
        guard let t0 = usable.first?.timestampSeconds else { return (nil, []) }
        // 실제 beat 인덱스 (누락 보정) — nominal period 기준 round.
        let indices = usable.map { Double(Int(round(($0.timestampSeconds - t0) / nominalPeriod))) }
        let times = usable.map { $0.timestampSeconds }
        let meanI = indices.reduce(0, +) / n
        let meanT = times.reduce(0, +) / n
        var sumXY: Double = 0
        var sumXX: Double = 0
        for i in 0..<usable.count {
            let dx = indices[i] - meanI
            let dy = times[i] - meanT
            sumXY += dx * dy
            sumXX += dx * dx
        }
        guard sumXX > 0 else { return (nil, []) }
        let slope = sumXY / sumXX
        let intercept = meanT - slope * meanI
        let residuals = (0..<usable.count).map { times[$0] - (slope * indices[$0] + intercept) }
        // Sanity: slope 이 nominal 의 ±3% 안에 있어야 (정확히 인덱스 보정됐다면 0.01% 정도).
        // ±3% 면 |rate| ≤ ~2600 s/d — 범위 매우 넓음. 그 이상은 fundamental 인덱싱 실패.
        let drift = abs(slope - nominalPeriod) / nominalPeriod
        if drift > 0.03 { return (nil, []) }
        return (slope, residuals)
    }

    /// Round 156 (Doyoon #7 fix): MAD = median(|x_i - median(x)|), 이전엔 median(|x|) 였음.
    /// RANSAC 임계값을 의도대로 좁혀 outlier rejection 강화 (이전엔 threshold 가 의도보다 커서 약했음).
    private static func medianAbsoluteDeviation(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sortedValues = values.sorted()
        let median = sortedValues[sortedValues.count / 2]
        let absDeviations = values.map { Swift.abs($0 - median) }.sorted()
        return absDeviations[absDeviations.count / 2]
    }

    /// Round 156 (Doyoon #8 fix): R² for slope fit — 정확한 OLS intercept 계산.
    /// 이전 코드는 `meanT - slope * (count-1)/2` 로 mean(index) 를 (count-1)/2 로 가정했으나
    /// RANSAC 필터링 후엔 임의 sparse index — 항상 옳지 않음. 실제 mean(index) 사용.
    private static func coefficientOfDetermination(beats: [BeatEvent], slope: Double) -> Double {
        guard beats.count >= 2 else { return 0 }
        let times = beats.map { $0.timestampSeconds }
        let indices = (0..<beats.count).map { Double($0) }
        let meanT = times.reduce(0, +) / Double(times.count)
        let meanI = indices.reduce(0, +) / Double(indices.count)
        let intercept = meanT - slope * meanI
        var ssTotal: Double = 0
        var ssResidual: Double = 0
        for i in 0..<beats.count {
            let predicted = slope * indices[i] + intercept
            ssTotal += (times[i] - meanT) * (times[i] - meanT)
            ssResidual += (times[i] - predicted) * (times[i] - predicted)
        }
        guard ssTotal > 0 else { return 0 }
        return max(0, 1.0 - ssResidual / ssTotal)
    }

    /// Round 158: Trimmed mean of IOIs — outlier (top/bottom 25%) 제거 후 평균.
    /// Histogram mode 의 bin boundary 영향 zero. Median 보다 더 많은 samples 사용으로 √2 정밀 향상.
    private func fallbackMedianRawBph(beats: [BeatEvent], bphEstimate: BPHEstimate) -> Double {
        guard beats.count >= 9 else { return bphEstimate.rawBph }
        let intervals = (1..<beats.count).map { beats[$0].timestampSeconds - beats[$0 - 1].timestampSeconds }
        let expected = 3600.0 / Double(bphEstimate.bph)
        // ±3% tight filter — 진짜 tic IOI 만 통과.
        let tight = intervals.filter { abs($0 - expected) <= expected * 0.03 }
        let pool: [Double] = tight.count >= 8 ? tight : intervals.filter { abs($0 - expected) <= expected * 0.10 }
        guard pool.count >= 8 else { return bphEstimate.rawBph }
        // Trimmed mean: 정렬 후 상위/하위 25% 제거, 중간 50% 평균.
        let sorted = pool.sorted()
        let trimStart = sorted.count / 4
        let trimEnd = sorted.count - sorted.count / 4
        let middle = Array(sorted[trimStart..<trimEnd])
        guard !middle.isEmpty else { return bphEstimate.rawBph }
        let trimmedMean = middle.reduce(0, +) / Double(middle.count)
        return 3600.0 / trimmedMean
    }

    static func estimateSNR(envelope: [Float], raw: [Float]) -> Double {
        guard !envelope.isEmpty else { return 0 }
        let sorted = envelope.sorted()
        let p10Idx = max(0, sorted.count / 10)
        let noiseFloor = sorted[p10Idx]
        let topStart = max(0, sorted.count - max(1, sorted.count / 20))
        let topSlice = sorted[topStart..<sorted.count]
        let peakAvg = topSlice.reduce(Float(0), +) / Float(topSlice.count)
        guard noiseFloor > 0, peakAvg > 0 else { return 0 }
        let ratio = Double(peakAvg) / Double(noiseFloor)
        return 20 * log10(max(ratio, 1))
    }

    // MARK: - Downsample (테스트용 + 내부 용)

    static func downsample(chunk: [Float], target: Int) -> [Float] {
        guard !chunk.isEmpty, target > 0 else { return [] }
        if chunk.count <= target {
            return normalized(chunk)
        }
        let step = Double(chunk.count) / Double(target)
        var result: [Float] = []
        result.reserveCapacity(target)
        var maxAbs: Float = 0
        for i in 0..<target {
            let from = Int(Double(i) * step)
            let to = min(chunk.count, Int(Double(i + 1) * step))
            var localMax: Float = 0
            if from < to {
                for j in from..<to {
                    let v = abs(chunk[j])
                    if v > localMax { localMax = v }
                }
            }
            if localMax > maxAbs { maxAbs = localMax }
            result.append(localMax)
        }
        guard maxAbs > 0 else { return result }
        let scale = 1.0 / maxAbs
        for i in 0..<result.count { result[i] *= scale }
        return result
    }

    static func normalized(_ chunk: [Float]) -> [Float] {
        var maxAbs: Float = 0
        for v in chunk where abs(v) > maxAbs { maxAbs = abs(v) }
        guard maxAbs > 0 else { return chunk }
        let scale = 1.0 / maxAbs
        return chunk.map { $0 * scale }
    }
}

```

## `WatchAccuracyPro/Core/DSP/Filters/BandPassFilter.swift`

```swift
import Accelerate
import Foundation

/// 2nd-order Butterworth band-pass (1kHz~10kHz @ 48kHz). 직접 비퀴드 구현.
/// 시계 tic/toc 에너지가 1~10kHz에 집중되므로 그 외 영역을 잘라 SNR을 높인다.
final class BandPassFilter {
    private let coeffsLow: BiquadCoefficients   // high-pass 1kHz
    private let coeffsHigh: BiquadCoefficients  // low-pass 10kHz
    private var stateLow = BiquadState()
    private var stateHigh = BiquadState()

    /// Round 37 (tickIQ 가 같은 환경 같은 순간 정확 lock — 우리 algorithm 결함 확정):
    /// 3-10kHz revert → **1-7kHz**. 시계마다 case 공명 다양 (1kHz 부터 10kHz 까지). 좁은 band 가 IWC
    /// 같은 일부 시계의 tic energy 차단했을 가능성. wider band 가 더 안전.
    // Round 130 (DSP 전문가 3명 합의): 1-7kHz → 2.5-7kHz 좁힘.
    // 1-2.5kHz 케이스 공명/HVAC hum 제거 → percentile noise floor 안정 → IWC 약 tic 검출률 ↑.
    init(sampleRate: Double = 48_000, lowCutoff: Double = 2_500, highCutoff: Double = 7_000) {
        self.coeffsLow = BiquadCoefficients.highPass(sampleRate: sampleRate, cutoff: lowCutoff, q: 0.707)
        self.coeffsHigh = BiquadCoefficients.lowPass(sampleRate: sampleRate, cutoff: highCutoff, q: 0.707)
    }

    func process(_ samples: [Float]) -> [Float] {
        let highPassed = stateLow.apply(coeffsLow, to: samples)
        return stateHigh.apply(coeffsHigh, to: highPassed)
    }

    func reset() {
        stateLow = BiquadState()
        stateHigh = BiquadState()
    }
}

/// Direct Form II Transposed biquad filter primitive.
struct BiquadCoefficients {
    let b0, b1, b2, a1, a2: Float

    static func highPass(sampleRate: Double, cutoff: Double, q: Double) -> BiquadCoefficients {
        let omega = 2 * .pi * cutoff / sampleRate
        let alpha = sin(omega) / (2 * q)
        let cosOmega = cos(omega)
        let b0 = (1 + cosOmega) / 2
        let b1 = -(1 + cosOmega)
        let b2 = (1 + cosOmega) / 2
        let a0 = 1 + alpha
        let a1 = -2 * cosOmega
        let a2 = 1 - alpha
        return .init(
            b0: Float(b0 / a0), b1: Float(b1 / a0), b2: Float(b2 / a0),
            a1: Float(a1 / a0), a2: Float(a2 / a0)
        )
    }

    static func lowPass(sampleRate: Double, cutoff: Double, q: Double) -> BiquadCoefficients {
        let omega = 2 * .pi * cutoff / sampleRate
        let alpha = sin(omega) / (2 * q)
        let cosOmega = cos(omega)
        let b0 = (1 - cosOmega) / 2
        let b1 = 1 - cosOmega
        let b2 = (1 - cosOmega) / 2
        let a0 = 1 + alpha
        let a1 = -2 * cosOmega
        let a2 = 1 - alpha
        return .init(
            b0: Float(b0 / a0), b1: Float(b1 / a0), b2: Float(b2 / a0),
            a1: Float(a1 / a0), a2: Float(a2 / a0)
        )
    }
}

struct BiquadState {
    var z1: Float = 0
    var z2: Float = 0

    mutating func apply(_ c: BiquadCoefficients, to samples: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            let x = samples[i]
            let y = c.b0 * x + z1
            z1 = c.b1 * x - c.a1 * y + z2
            z2 = c.b2 * x - c.a2 * y
            out[i] = y
        }
        return out
    }
}

/// Round 153 (Kim+Chen+Müller 토론): caliber-adaptive BandPass + envelope cutoff spec.
/// MatchedFilterProfile.resolve(...) 와 동일 dispatch — single source of truth.
/// 28800 BPH swissLever 는 production default 와 동일 → 회귀 zero.
struct BandPassSpec {
    let lowHz: Double
    let highHz: Double
    let envCutoffHz: Double

    // Round 158 (tickIQ deep analysis): tickIQ filter 가 2-5kHz 영역 -50dB 제거, 8-15kHz 영역 보존/boost.
    // 우리 2.5-7kHz 는 tickIQ 가 *무시하는* 영역 통과시킴. 6-15kHz 로 이동 — high-freq tic transient 영역.
    static let `default` = BandPassSpec(lowHz: 6_000, highHz: 15_000, envCutoffHz: 500)

    static func spec(for profile: MatchedFilterProfile, escapement: Escapement) -> BandPassSpec {
        // co-axial: matched filter 는 bypass 지만 BP 는 wide-band 로 sub-pulse 보존.
        if escapement == .coAxial {
            return .init(lowHz: 2_000, highHz: 9_000, envCutoffHz: 400)
        }
        switch profile {
        case .bypass:                 return .default
        case .vintage18k:             return .init(lowHz: 1_500, highHz: 5_000, envCutoffHz: 250)
        case .swissLever21600:        return .init(lowHz: 2_000, highHz: 6_000, envCutoffHz: 300)
        case .swissLever28800Classic: return .default  // 현재 production 값과 동일 (회귀 zero).
        case .highBeat36000:          return .init(lowHz: 3_500, highHz: 8_000, envCutoffHz: 500)
        }
    }
}

```

## `WatchAccuracyPro/Core/DSP/Filters/EnvelopeExtractor.swift`

```swift
import Accelerate
import Foundation

/// 신호 진폭 envelope 추출 — abs() + 1차 IIR low-pass.
/// Hilbert transform 보다 간단하고 tic/toc 펄스 검출에는 충분하다.
final class EnvelopeExtractor {
    private let alpha: Float // smoothing factor
    private var state: Float = 0

    /// `cutoffHz` 가 envelope 의 시간상수를 결정.
    /// **Audit 권고**: 200Hz (τ 0.8ms) 가 5ms tic 을 14dB 평탄화. 350Hz (τ 0.45ms) 로 sharper peak 보존.
    init(sampleRate: Double = 48_000, cutoffHz: Double = 350) {
        let dt = 1.0 / sampleRate
        let rc = 1.0 / (2.0 * .pi * cutoffHz)
        self.alpha = Float(dt / (rc + dt))
    }

    func process(_ samples: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: samples.count)
        // 절댓값 (벡터화)
        var abs = [Float](repeating: 0, count: samples.count)
        vDSP.absolute(samples, result: &abs)
        // 1-pole IIR low-pass: y[n] = a*x[n] + (1-a)*y[n-1]
        var prev = state
        for i in 0..<abs.count {
            prev = alpha * abs[i] + (1 - alpha) * prev
            out[i] = prev
        }
        state = prev
        return out
    }

    func reset() { state = 0 }
}

```

## `WatchAccuracyPro/Core/DSP/Filters/MatchedFilter.swift`

```swift
import Accelerate
import Foundation

/// Matched filter cross-correlation for mechanical watch tic detection.
///
/// Industry-standard 접근 (vacaboja/tg, Watch-O-Scope 의 핵심 알고리즘).
/// 합성 watch tic template (Gabor pulse: 5500Hz 중심, 5ms duration, gaussian envelope)
/// 과 cross-correlation. tic-like transient 만 강한 응답, broadband noise 는 약한 응답.
///
/// 동작:
/// - input: bandpass 통과한 audio-rate signal (48kHz)
/// - output: 같은 length 의 |cc(n)| — 각 위치에서 template 와의 매칭 강도
/// - 그 output 이 envelope/flux extractor 의 입력으로 들어가면, 결과 onset signal 이
///   훨씬 robust (noise dominant 환경에서도 tic shape 만 강조).
///
/// 일반 RMS-based envelope 대비 장점: amplitude 변동에 강함, broadband noise 거의 reject.
/// Round 151 (Müller + Kim 토론): 캘리버 family 별 matched filter profile.
/// Round 37 IWC mismatch 회피 — escapement + bph 기반 dispatch.
enum MatchedFilterProfile: Equatable {
    case bypass                               // coAxial / springDrive / quartz / detent
    case vintage18k                           // 18000 BPH swissLever (ETA 2750 등)
    case swissLever21600                      // ETA 2824, SW200 vintage
    case swissLever28800Classic               // ETA 2892, Rolex 3135, IWC 35111 (Round 156: Modern 통합)
    case highBeat36000                        // Zenith El Primero, GS 9S86

    var centerFrequencyHz: Double? {
        switch self {
        case .bypass: return nil
        case .vintage18k: return 4_000
        case .swissLever21600: return 5_000
        case .swissLever28800Classic: return 5_800
        case .highBeat36000: return 7_500
        }
    }
    var durationMs: Double? {
        switch self {
        case .bypass: return nil
        case .vintage18k: return 9.0
        case .swissLever21600: return 6.0
        case .swissLever28800Classic: return 5.0
        case .highBeat36000: return 3.5
        }
    }

    /// escapement + bph → profile. 안 맞으면 .bypass (Round 37 회피).
    /// Round 156 (Hyemi #4 fix): swissLever28800Modern 는 resolve 에서 도달 불가능한 dead path 였음
    /// (25_200..<31_500 → Classic 만 반환). 향후 composite Gabor template 도입 시 별도 함수로 분리하여 추가 예정.
    static func resolve(escapement: Escapement, bph: Int) -> MatchedFilterProfile {
        switch escapement {
        case .coAxial, .springDrive, .quartz, .detentEscapement:
            return .bypass
        case .swissLever, .siliconEscapement:
            switch bph {
            case ..<19_800: return .vintage18k
            case 19_800..<25_200: return .swissLever21600
            case 25_200..<31_500: return .swissLever28800Classic
            case 31_500...: return .highBeat36000
            default: return .bypass
            }
        }
    }
}

final class MatchedFilter {
    /// Gabor pulse template — 시계 tic acoustic signature 모방.
    private let template: [Float]
    /// Chunk boundary carry — process 가 chunk 단위로 호출될 때 boundary M-1 sample 보존.
    private var carry: [Float] = []
    private let templateSize: Int
    let profile: MatchedFilterProfile

    /// Round 151: profile 기반 init. `.bypass` 면 template 0 length → process() 는 input 그대로 반환.
    init(profile: MatchedFilterProfile, sampleRate: Double = 48_000) {
        self.profile = profile
        if let f = profile.centerFrequencyHz, let d = profile.durationMs {
            self.template = Self.gaborTemplate(
                sampleRate: sampleRate, centerFreq: f, durationMs: d
            )
        } else {
            self.template = []
        }
        self.templateSize = template.count
    }

    /// 레거시 init — 호환성 유지 (직접 5500 Hz 호출 코드 잔존 시).
    init(sampleRate: Double = 48_000, centerFrequencyHz: Double = 5_500, durationMs: Double = 5.0) {
        self.profile = .swissLever28800Classic
        self.template = Self.gaborTemplate(
            sampleRate: sampleRate,
            centerFreq: centerFrequencyHz,
            durationMs: durationMs
        )
        self.templateSize = template.count
    }

    /// Gabor pulse: gaussian envelope × sinusoid. 시계 tic 의 dominant freq 5-7kHz 영역 모방.
    /// (ETA 7750 / 2824 / Sellita SW200 등 popular movement 의 acoustic signature 와 align.)
    private static func gaborTemplate(sampleRate: Double, centerFreq: Double, durationMs: Double) -> [Float] {
        let N = max(8, Int(durationMs / 1000.0 * sampleRate))
        let center = durationMs / 2000.0       // 중심 시각 (s)
        let sigma = durationMs / 4000.0         // gaussian width — duration 의 1/4
        var t = [Float](repeating: 0, count: N)
        for i in 0..<N {
            let time = Double(i) / sampleRate
            let env = exp(-((time - center) * (time - center)) / (2 * sigma * sigma))
            let sinusoid = sin(2 * .pi * centerFreq * time)
            t[i] = Float(env * sinusoid)
        }
        // Normalize — sum of squares = 1.
        var sumSq: Float = 0
        for v in t { sumSq += v * v }
        let norm = sqrt(sumSq)
        if norm > 0 {
            for i in 0..<N { t[i] /= norm }
        }
        return t
    }

    func reset() { carry.removeAll() }

    /// `samples` 위에 matched filter 적용. carry 와 합쳐 cc 결과 (same length as `samples`) 반환.
    /// 마지막 M-1 sample 은 다음 chunk 와 boundary 처리 (carry 로 보존).
    func process(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        // Round 151 (Müller Layer 3): bypass profile — input 그대로 반환 (no-op).
        if templateSize == 0 { return samples }
        let buffer = carry + samples
        let N = buffer.count
        let M = templateSize
        guard N >= M else {
            carry = buffer
            return [Float](repeating: 0, count: samples.count)
        }
        // cc 계산 — buffer 의 0..N-M+1 에서. 각 position 에서 template 와 dot product.
        let ccLength = N - M + 1
        var cc = [Float](repeating: 0, count: ccLength)
        buffer.withUnsafeBufferPointer { bp in
            template.withUnsafeBufferPointer { tp in
                for n in 0..<ccLength {
                    var v: Float = 0
                    vDSP_dotpr(bp.baseAddress!.advanced(by: n), 1, tp.baseAddress!, 1, &v, vDSP_Length(M))
                    cc[n] = abs(v)
                }
            }
        }
        // Carry: 다음 chunk 와 overlap 위해 마지막 M-1 sample 보존.
        carry = Array(buffer.suffix(M - 1))
        // Return: samples 길이 만큼만. carry 영역 (buffer 의 처음 carry-prev 길이) 만큼 잘라낸 후.
        // 단순화 — cc 의 마지막 samples.count 만큼 반환. boundary 정확도 약간 잃지만 OK.
        if cc.count >= samples.count {
            return Array(cc.suffix(samples.count))
        } else {
            return cc + [Float](repeating: 0, count: samples.count - cc.count)
        }
    }
}

```

## `WatchAccuracyPro/Core/DSP/Filters/MultiBandEnvelope.swift`

```swift
import Accelerate
import Foundation

/// Round 158 (Wang Stanford CCRMA 권고): Multi-band envelope fusion.
///
/// 사용자 IWC IW371604 (Cal.35111 sapphire-back) 측정 실패 — single bandpass 가
/// frequency-dependent attenuation 에 취약. Sapphire case back 은 high-freq -10dB 감쇠
/// → 5-7kHz 만 보는 single BP 는 신호 못 잡음.
///
/// 해결: 3 octave-spaced bands 병렬 처리 + max fusion.
/// - Band 1: 1-3 kHz (low impulse / mechanical resonance)
/// - Band 2: 3-6 kHz (mid-frequency lock event)
/// - Band 3: 6-10 kHz (high impulse / drop event)
///
/// 각 band 별 envelope (abs + LPF) 계산 후 sample-wise max → 어느 band 든 신호 있으면 살아남음.
final class MultiBandEnvelope {
    private let bands: [(bp: BandPassFilter, env: EnvelopeExtractor)]

    init(sampleRate: Double = 48_000) {
        // Wang 권고: octave-spaced bands.
        let bandSpecs: [(low: Double, high: Double, envCutoff: Double)] = [
            (1_000, 3_000, 400),  // low: mechanical resonance
            (3_000, 6_000, 400),  // mid: lock event
            (6_000, 10_000, 400)  // high: impulse/drop
        ]
        self.bands = bandSpecs.map { spec in
            (
                bp: BandPassFilter(sampleRate: sampleRate, lowCutoff: spec.low, highCutoff: spec.high),
                env: EnvelopeExtractor(sampleRate: sampleRate, cutoffHz: spec.envCutoff)
            )
        }
    }

    /// 입력 raw audio → max-fused multi-band envelope.
    func process(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        // 각 band 별 envelope 계산.
        let envelopes: [[Float]] = bands.map { band in
            let bp = band.bp.process(samples)
            return band.env.process(bp)
        }
        // Sample-wise max fusion — 어느 band 든 강한 신호 있으면 살아남음.
        var fused = [Float](repeating: 0, count: samples.count)
        for env in envelopes {
            for i in 0..<min(env.count, fused.count) {
                if env[i] > fused[i] { fused[i] = env[i] }
            }
        }
        return fused
    }

    func reset() {
        bands.forEach { band in
            band.bp.reset()
            band.env.reset()
        }
    }
}

```

## `WatchAccuracyPro/Core/DSP/Filters/NoiseFloorSuppressor.swift`

```swift
import Accelerate
import Foundation

/// Round 158: tickIQ output 분석 (raw RMS -73dB → filtered RMS -93dB, crest 2.6 → 9.5) 기반.
/// time-domain noise floor subtraction + transient emphasis.
///
/// 동작:
/// 1. Slow running mean (baseline) — long time constant LPF (예: 50ms RC)
/// 2. Signal - baseline → centered (DC-free, baseline-free)
/// 3. Half-wave rectification (양수만 유지 — tic 가 baseline 위로 솟은 부분만)
/// 4. Soft knee — sub-noise 영역 zero out
///
/// 결과: tic transient 만 살아남는 sparse signal. Autocorrelation 자가상관 peak 강화.
final class NoiseFloorSuppressor {
    private let sampleRate: Double
    private let baselineAlpha: Float  // slow LPF
    private let envelopeAlpha: Float  // fast envelope LPF (abs follower)
    private var baselineState: Float = 0
    private var envelopeState: Float = 0
    /// Adaptive noise floor estimate — 매우 느린 LPF (5초 시정수).
    private var noiseFloorState: Float = 0
    private let noiseFloorAlpha: Float

    /// `baselineCutoffHz`: baseline tracker cutoff (10-50Hz 권장).
    /// `gateRatio`: 신호가 baseline 의 몇 배 이상이어야 통과 (1.5-3.0 권장).
    let gateRatio: Float

    init(sampleRate: Double = 48_000,
         baselineCutoffHz: Double = 20,
         envelopeCutoffHz: Double = 400,
         gateRatio: Float = 1.5) {
        self.sampleRate = sampleRate
        self.gateRatio = gateRatio
        let dt = 1.0 / sampleRate
        // Baseline tracker — slow.
        let rcBaseline = 1.0 / (2.0 * .pi * baselineCutoffHz)
        self.baselineAlpha = Float(dt / (rcBaseline + dt))
        // Envelope follower — fast.
        let rcEnvelope = 1.0 / (2.0 * .pi * envelopeCutoffHz)
        self.envelopeAlpha = Float(dt / (rcEnvelope + dt))
        // Noise floor — very slow (5s time constant).
        let rcNoise = 5.0
        self.noiseFloorAlpha = Float(dt / (rcNoise + dt))
    }

    /// raw audio (bandpass 후) → noise-suppressed envelope.
    func process(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        // Step 1: abs (rectified).
        var abs = [Float](repeating: 0, count: samples.count)
        vDSP.absolute(samples, result: &abs)
        // Step 2: fast envelope (sharp peak preserve).
        var envelope = [Float](repeating: 0, count: samples.count)
        var envState = envelopeState
        for i in 0..<abs.count {
            envState = envelopeAlpha * abs[i] + (1 - envelopeAlpha) * envState
            envelope[i] = envState
        }
        envelopeState = envState
        // Step 3: slow baseline tracker (background noise level).
        var baseline = [Float](repeating: 0, count: samples.count)
        var baseState = baselineState
        for i in 0..<envelope.count {
            baseState = baselineAlpha * envelope[i] + (1 - baselineAlpha) * baseState
            baseline[i] = baseState
        }
        baselineState = baseState
        // Step 4: noise floor estimate (very slow, captures sustained noise).
        var noiseFloor = noiseFloorState
        for v in baseline {
            noiseFloor = noiseFloorAlpha * v + (1 - noiseFloorAlpha) * noiseFloor
        }
        noiseFloorState = noiseFloor
        // Step 5: subtract baseline, gate with ratio, half-wave rectify.
        // y[n] = max(0, envelope[n] - baseline[n] × gateRatio).
        var out = [Float](repeating: 0, count: samples.count)
        for i in 0..<envelope.count {
            let threshold = baseline[i] * gateRatio
            let above = envelope[i] - threshold
            out[i] = above > 0 ? above : 0
        }
        return out
    }

    func reset() {
        baselineState = 0
        envelopeState = 0
        noiseFloorState = 0
    }
}

```

## `WatchAccuracyPro/Core/DSP/Filters/NoiseSuppressor.swift`

```swift
import Accelerate
import Foundation

/// Industry-standard 노이즈 억제 (vacaboja/tg `noise_suppressor` port).
///
/// 동작: envelope 를 N ms window 로 나눠 각 window 의 squared energy 계산. 매 0.5s 의
/// per-window max 들의 median 을 baseline noise 로 산정. 어떤 window 의 energy 가 그
/// baseline × threshold 초과면 그 window 의 전체 sample 을 0 으로 만듦.
///
/// 효과: 한 거대 spike (마이크 contact noise, 손가락 움직임, 도어 슬램 등) 가
/// envelope/flux 위에서 BPHEstimator 의 autocorr 와 BeatDetector 의 threshold 다 망치는 효과 차단.
/// 사용자 보고된 "거대 spike 1개로 onset 47/121/162 잘못 잡힘" 케이스 해결.
enum NoiseSuppressor {
    /// - Parameters:
    ///   - envelope: 입력 envelope (audio-rate 또는 decimated 둘 다 가능).
    ///   - sampleRate: envelope 의 sample rate.
    ///   - windowMs: energy 윈도우 크기 (기본 20ms — tg 와 동일).
    ///   - thresholdRatio: baseline 대비 몇 배 초과 시 zero out (기본 4.0 — tg 의 2.0 보다 관대,
    ///     iPhone mic 의 normal tic 변동성이 desktop mic 보다 큼).
    static func suppress(
        _ envelope: [Float],
        sampleRate: Double,
        windowMs: Double = 20,
        thresholdRatio: Float = 4.0
    ) -> [Float] {
        guard !envelope.isEmpty else { return envelope }
        let windowSamples = max(1, Int(windowMs / 1_000 * sampleRate))
        let numWindows = (envelope.count + windowSamples - 1) / windowSamples
        guard numWindows >= 2 else { return envelope }

        // 1) 각 window 의 squared energy 합 계산.
        var energies = [Float](repeating: 0, count: numWindows)
        for w in 0..<numWindows {
            let lo = w * windowSamples
            let hi = min(envelope.count, lo + windowSamples)
            var sum: Float = 0
            for i in lo..<hi {
                let v = envelope[i]
                sum += v * v
            }
            energies[w] = sum
        }

        // 2) Baseline = median of all window energies.
        //    (tg 는 매 0.5s 의 per-window max 의 median 사용. 우리는 단순화.)
        let sorted = energies.sorted()
        let median = sorted[sorted.count / 2]
        guard median > 0 else { return envelope }
        let threshold = median * thresholdRatio

        // 3) Threshold 초과 window 의 전체 sample 을 0 으로.
        var suppressed = envelope
        for w in 0..<numWindows where energies[w] > threshold {
            let lo = w * windowSamples
            let hi = min(suppressed.count, lo + windowSamples)
            for i in lo..<hi { suppressed[i] = 0 }
        }
        return suppressed
    }
}

```

## `WatchAccuracyPro/Core/DSP/Filters/PreEmphasisFilter.swift`

```swift
import Foundation

/// 1차 high-pass pre-emphasis: y[n] = x[n] - a*x[n-1]
/// `coefficient` 0.95 정도면 ~1kHz 위 주파수 +6dB/oct 부스트.
/// stateful 한 이유: 청크 경계에서도 연속성을 유지해야 하기 때문.
///
/// 사용자 보고: "조용한 곳에서 핸드폰 붙였는데도 감지 못 함" — 0.97 은 24kHz 에서 +36dB
/// 부스트라 마이크 자체 잡음을 증폭하는 부작용. coefficient 0.0 이면 identity (skip).
/// 실 watch tic 은 1-8kHz 에 충분한 에너지가 있어 pre-emphasis 없이도 BandPass 로 충분히 잡힘.
final class PreEmphasisFilter {
    private let coefficient: Float
    private var lastSample: Float = 0

    // Round 130 (Chen P3 + Müller §3): 0.0 → 0.5. IWC 같은 케이스 댐핑 시계 고주파 tic 강조.
    // 0.5는 0.0(bypass)과 0.97(과대 noise) 절충. transient sharpness 우선.
    init(coefficient: Float = 0.5) {
        self.coefficient = coefficient
    }

    func process(_ samples: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: samples.count)
        var prev = lastSample
        for i in 0..<samples.count {
            let x = samples[i]
            out[i] = x - coefficient * prev
            prev = x
        }
        lastSample = prev
        return out
    }

    func reset() { lastSample = 0 }
}

```

## `WatchAccuracyPro/Core/DSP/Filters/SpectralFluxExtractor.swift`

```swift
import Accelerate
import Foundation

/// Spectral-flux-style transient detector (Audit 4 권고로 도입).
///
/// 기존 abs + IIR LP envelope 가 watch tic 의 sharp onset (~0.5-1ms) 을 1.6ms 시상수로 평탄화하여
/// autocorrelation/onset detection 둘 다 실패하던 문제 근본 해결.
///
/// 알고리즘:
/// 1. BandPass (1-7kHz) 후 신호를 5ms (240 samples @ 48kHz) 비중첩 윈도우로 chunk
/// 2. 각 윈도우의 RMS energy 계산
/// 3. **Half-wave rectified diff** = max(0, energy[t] - energy[t-1])
/// 4. 출력: 200 Hz rate 의 transient 신호 (rising edge 만 강조)
///
/// FFT 없이도 spectral flux 의 핵심 효과 (transient onset 보존) 달성.
/// 출력은 watch tic 마다 sharp peak 가 있고 그 사이는 거의 0 인 신호 → BPH lock 매우 쉬움.
final class SpectralFluxExtractor {
    /// 5ms hop @ 48kHz = 240 샘플. 출력 sampleRate = 200 Hz.
    static let frameSize = 240
    static let outputSampleRate: Double = 200.0

    private var prevEnergy: Float = 0
    private var carry: [Float] = []

    /// BandPass 후 raw 샘플을 입력. 출력: 200 Hz flux 시계열 (frame 별 1 샘플).
    func process(_ samples: [Float]) -> [Float] {
        var combined = carry
        combined.append(contentsOf: samples)
        var flux: [Float] = []
        var i = 0
        let n = combined.count
        while i + Self.frameSize <= n {
            var ms: Float = 0
            // RMS — vDSP 가속 (제곱합 / N → sqrt)
            combined.withUnsafeBufferPointer { ptr in
                let base = ptr.baseAddress!.advanced(by: i)
                vDSP_svesq(base, 1, &ms, vDSP_Length(Self.frameSize))
            }
            let energy = sqrt(ms / Float(Self.frameSize))
            let f = Swift.max(0, energy - prevEnergy)
            flux.append(f)
            prevEnergy = energy
            i += Self.frameSize
        }
        // 남은 샘플은 다음 chunk 와 합쳐 처리.
        if i < n {
            carry = Array(combined[i..<n])
        } else {
            carry.removeAll(keepingCapacity: true)
        }
        return flux
    }

    func reset() {
        prevEnergy = 0
        carry.removeAll(keepingCapacity: true)
    }
}

```

## `WatchAccuracyPro/Core/DSP/LinearRegressionRate.swift`

```swift
import Foundation

/// Linear least-squares regression on cumulative beat positions vs time.
///
/// Industry-standard approach (vacaboja/tg, Watch-O-Scope manual).
/// 누적 beat index (0, 1, 2, ..., N-1) vs timestamps 의 LSQ regression.
/// slope = seconds per beat → BPH 추정.
/// 단일 IOI median 보다 정확 (N 개 beat 의 noise 평균화 + sub-sample timestamp 활용).
///
/// 정밀도: noise level σ 일 때 slope 정밀도 ~ σ/√N. 30s 측정 240 beat + sub-sample timestamp
/// 정밀도 ±0.02ms 가정 시 rate 정밀도 약 ±1 s/d 이내.
///
/// Round 39 (사용자 보고: live rate +0.0 quantization): IOI median 기반 calc 의 한계 극복.
enum LinearRegressionRate {
    /// beats 의 cumulative position 위 LSQ regression. slope = sec per beat.
    /// - Returns: (slope, rSquared) — slope: sec/beat, rSquared: fit 품질 [0,1].
    static func slopeSecondsPerBeat(beats: [BeatEvent]) -> (slope: Double, rSquared: Double)? {
        guard beats.count >= 4 else { return nil }
        let n = Double(beats.count)
        // x_i = beat index, y_i = timestamp.
        var sumX: Double = 0, sumY: Double = 0
        for i in 0..<beats.count {
            sumX += Double(i)
            sumY += beats[i].timestampSeconds
        }
        let meanX = sumX / n
        let meanY = sumY / n
        var num: Double = 0, denX: Double = 0, denY: Double = 0
        for i in 0..<beats.count {
            let dx = Double(i) - meanX
            let dy = beats[i].timestampSeconds - meanY
            num += dx * dy
            denX += dx * dx
            denY += dy * dy
        }
        guard denX > 0, denY > 0 else { return nil }
        let slope = num / denX
        let r = num / sqrt(denX * denY)
        return (slope, r * r)
    }

    /// LSQ 기반 정밀 BPH 추정.
    static func bph(beats: [BeatEvent]) -> Double? {
        guard let (slope, _) = slopeSecondsPerBeat(beats: beats), slope > 0 else { return nil }
        return 3_600.0 / slope
    }

    /// LSQ 기반 정밀 rate (sec/day) 추정.
    /// - Parameters:
    ///   - beats: 정밀 timestamp 의 beat events (`refineTimestamps` 후).
    ///   - nominalBph: 명목 BPH.
    static func secondsPerDay(beats: [BeatEvent], nominalBph: Int) -> Double? {
        guard nominalBph > 0, let measuredBph = bph(beats: beats) else { return nil }
        return (measuredBph - Double(nominalBph)) / Double(nominalBph) * 86_400
    }
}

```

## `WatchAccuracyPro/Core/DSP/MeasurementResult.swift`

```swift
import Foundation

/// 측정 결과 화면에 부여될 신뢰도 안내. UI 가 title/body 모두 keyset 으로 매핑.
/// Round 7 (Doyoon/Min): String typo 방지 위해 enum 으로.
enum ReliabilityNote: String, Sendable, Hashable, Codable {
    case coaxial          = "movement.reliability.coaxial.notice"
    case generic          = "movement.reliability.generic.notice"
    case amplitudeUnstable = "movement.reliability.amplitude_unstable.notice"

    var titleKey: String {
        switch self {
        case .coaxial:           return "movement.reliability.coaxial.title"
        case .amplitudeUnstable: return "movement.reliability.amplitude_unstable.title"
        case .generic:           return "movement.reliability.generic.title"
        }
    }

    var bodyKey: String { rawValue }
}

/// Round 152 (Müller+Chen+Min 토론): 측정 신뢰도 등급 — A/B/C/F.
/// confidence 0-100 + cross-window rate delta 종합 평가. 사용자 friendly 표시.
enum ReliabilityGrade: String, Sendable, Hashable, Codable {
    case a, b, c, f

    /// Chen 권장 임계 — 실측 분포 반영. A≥75 (이전 토론 85 보다 완화).
    /// Round 154 사용자 실측: 임계 10 → 25 s/d 로 완화 (모바일 환경 자연 stddev).
    static func from(confidence: Int, crossWindowDelta: Double?) -> ReliabilityGrade {
        from(confidence: confidence, crossWindowDelta: crossWindowDelta, rateSecondsPerDay: 0)
    }

    /// Round 158 (사용자 보고: Grade B 인데 +157 s/d): rate 절대값 기반 추가 penalty.
    /// 정상 시계는 ±50 s/d 이내. |rate| 큰 측정은 consistency 무관하게 grade 낮춤.
    static func from(confidence: Int, crossWindowDelta: Double?, rateSecondsPerDay: Double) -> ReliabilityGrade {
        let windowPenalty: Int = {
            guard let d = crossWindowDelta, d > 25 else { return 0 }
            return Int(min(20, d - 25))
        }()
        let absRate = abs(rateSecondsPerDay)
        let ratePenalty: Int = {
            // |rate| > 50 부터 점진 penalty, |rate| > 100 면 매우 강함.
            if absRate <= 30 { return 0 }
            if absRate <= 60 { return Int(absRate - 30) }  // 0-30
            if absRate <= 120 { return 30 + Int((absRate - 60) / 2) }  // 30-60
            return 60  // |rate| > 120 → 항상 F-grade
        }()
        let adjusted = confidence - windowPenalty - ratePenalty
        switch adjusted {
        case 75...: return .a
        case 55..<75: return .b
        case 35..<55: return .c
        default: return .f
        }
    }
}

/// DSPPipeline 의 분석 산출물. UI 표시용 + SwiftData 저장용 중간 모델.
struct MeasurementResult: Equatable, Hashable, Sendable {
    let bph: Int
    let rateSecondsPerDay: Double
    let beatErrorMs: Double
    /// 코악시얼/스프링드라이브 또는 추정 실패 시 nil.
    let amplitudeDegrees: Double?
    let confidenceScore: Int
    let durationSeconds: Int
    let snrDB: Double
    let beatCount: Int
    /// 코악시얼 등 reliability 가 medium/low 또는 amplitude 추정 실패 시 부여.
    let reliabilityNote: ReliabilityNote?
    /// 측정 시 사용자가 선택한 자세. nil/.unknown 이면 "미지정".
    var position: Position = .unknown
    /// Round 152 (Müller H1): 30s 측정을 3개 10s sub-window 로 나눠 rate max-min 차이. nil 이면 평가 안 됨.
    var crossWindowRateDelta: Double? = nil
    /// Round 152: 사용자 표시용 신뢰도 등급. nil 이면 legacy (.from 으로 fallback 가능).
    var reliabilityGrade: ReliabilityGrade? = nil
    /// Round 170 (팀 토론): OLS residual RMS (seconds). rate 정밀도 직접 metric — internal gate 용.
    /// ±1 s/d 목표 시 240 beats 면 RMS ≤ 22μs, 96 beats 면 ≤ 35μs.
    var residualRMSSeconds: Double? = nil

    /// 후방 호환 — UI 가 String key 를 직접 다루는 코드가 있으면 이 프로퍼티 사용.
    var reliabilityNoteKey: String? { reliabilityNote?.rawValue }
}

/// 진행 중 측정의 라이브 메트릭 — UI 갱신용 스트림 페이로드.
struct LiveMetrics: Sendable, Equatable {
    var bph: Int?
    var rateSecondsPerDay: Double?
    var beatErrorMs: Double?
    var amplitudeDegrees: Double?
    var confidenceScore: Int
    var elapsedSeconds: Double
    /// envelope 기반 SNR (dB). BPH 락 후에만 의미 있음.
    var snrDB: Double?
    /// raw 마이크 RMS in dBFS (-∞ ~ 0). 마이크 자체가 신호 받고 있는지 확인용.
    var rawRMSDB: Double?
    /// 검출된 onset (tic) 개수 — 신호 주기성 체크.
    var onsetCount: Int?
    /// envelope peak/floor ratio — 신호 명료도.
    var envelopeDynamicRange: Double?
    /// Round 32 (Min): BPH lock 실패 시 어느 layer 에서 막혔는지. UI 진단 strip 에 노출.
    /// 사용자 보고: 91/70/117/47 onsets 어느 케이스도 lock 실패 — 그 동안 어떤 path 가 reject 했는지 모름.
    var lockFailReason: String?
    // Round 153 (Doyoon+Chen+Min coaching): 사용자 시각 피드백 점수.
    /// 0-100. rawRMSDB [-50, -20] dBFS linear remap. nil = 데이터 부족.
    var micContactScore: Int? = nil
    /// 0-100. 직전 5초 rate ring stddev → 역지수 매핑.
    var lockStabilityScore: Int? = nil
    /// Pro mode 진단용 — rate 의 rolling std-dev (s/d).
    var rateRollingStdDev: Double? = nil
    /// 사용자 요청: 실시간 tic/toc 점 시각화 — 최근 검출 onset 시각 (측정 시작 기준 seconds).
    /// 알고리즘 자체는 unchanged — 기존 detection 결과 외부 노출 전용. nil 이면 빈 화면.
    var recentOnsetTimes: [Double]? = nil
}

/// 라이브 파형 표시용 페이로드. -1...1 범위 다운샘플 진폭 + 측정 시작부터의 경과 시각.
struct LiveWaveformChunk: Sendable, Equatable {
    /// 200개 정도로 다운샘플된 -1...1 범위 진폭.
    var samples: [Float]
    var elapsedSeconds: Double
}

```

## `WatchAccuracyPro/Core/DSP/PLLTracker.swift`

```swift
import Foundation

/// Round 158: Phase-Locked Loop tracking — Müller/Wang 패널 권고 구현.
///
/// 동작:
/// 1. 첫 N개 onset 으로 초기 period 추정 (median IOI)
/// 2. 각 후속 onset: 예상 phase 와 비교 → ±tolerance 안이면 lock 유지 + period 미세조정
/// 3. 예상 시점 ±tolerance 밖 onset 은 outlier — reject
/// 4. Lock 잃으면 (consecutive miss > maxMiss) → reset
///
/// 결과: sub-pulse drift 영향 차단, period 안정 추적.
final class PLLTracker {
    /// 현재 period 추정 (seconds)
    private(set) var period: Double
    /// 마지막 lock 시각 (seconds, 신호 시작 기준)
    private(set) var lastLockTime: Double = 0
    /// 누적 lock 횟수
    private(set) var lockCount: Int = 0
    /// 연속 miss 횟수
    private var consecutiveMiss: Int = 0

    /// Tolerance — 예상 phase 대비 ±toleranceFraction × period 안이면 lock.
    let toleranceFraction: Double
    /// Period 학습률 (1차 IIR alpha). 작을수록 안정, 클수록 빠른 적응.
    let learningRate: Double
    /// 최대 연속 miss — 이 이상이면 lock 잃은 것으로 간주.
    let maxConsecutiveMiss: Int

    init(initialPeriod: Double,
         toleranceFraction: Double = 0.08,  // ±8% = 28800 의 ±10ms
         learningRate: Double = 0.05,
         maxConsecutiveMiss: Int = 5) {
        self.period = initialPeriod
        self.toleranceFraction = toleranceFraction
        self.learningRate = learningRate
        self.maxConsecutiveMiss = maxConsecutiveMiss
    }

    /// PLL 초기화 — 첫 onset 으로 phase 설정.
    func bootstrap(firstOnset: Double) {
        lastLockTime = firstOnset
        lockCount = 1
        consecutiveMiss = 0
    }

    /// 후속 onset 시도. lock 성공 시 true 반환 + period 업데이트.
    /// 예상 시점 = lastLockTime + period (× 정수배 — onset 1개 또는 여러 개 미스 후 가능)
    @discardableResult
    func tryLock(onsetTime: Double) -> Bool {
        guard lockCount > 0 else {
            bootstrap(firstOnset: onsetTime)
            return true
        }
        // 예상 phase 후보 (1, 2, 3 period 후 — missed beat 보상)
        let elapsed = onsetTime - lastLockTime
        guard elapsed > 0 else { return false }
        let nearestK = max(1, Int(round(elapsed / period)))
        let expected = lastLockTime + Double(nearestK) * period
        let phaseError = onsetTime - expected
        let tolerance = period * toleranceFraction
        guard abs(phaseError) <= tolerance else {
            consecutiveMiss += 1
            if consecutiveMiss > maxConsecutiveMiss {
                // Lock 잃음 — reset 으로 새로운 phase 시작.
                bootstrap(firstOnset: onsetTime)
            }
            return false
        }
        // Lock 성공 — period 미세조정 (IIR).
        let measuredPeriod = (onsetTime - lastLockTime) / Double(nearestK)
        period = (1 - learningRate) * period + learningRate * measuredPeriod
        lastLockTime = onsetTime
        lockCount += 1
        consecutiveMiss = 0
        return true
    }

    /// 다음 예상 onset 시간.
    func nextExpected() -> Double {
        lastLockTime + period
    }
}

```

## `WatchAccuracyPro/Core/DSP/RateCalculator.swift`

```swift
import Foundation

/// 측정된 BPH와 명목 BPH의 차이로부터 일일 오차(초/일)를 계산한다.
enum RateCalculator {
    /// - Parameters:
    ///   - measuredBph: BPHEstimator가 산출한 raw BPH
    ///   - nominalBph: 무브먼트 DB의 명목 BPH (예: 28800)
    /// - Returns: 양수면 시계가 빠름, 음수면 느림. 단위 초/일.
    static func secondsPerDay(measuredBph: Double, nominalBph: Int) -> Double {
        guard nominalBph > 0 else { return 0 }
        let ratio = (measuredBph - Double(nominalBph)) / Double(nominalBph)
        return ratio * 86_400
    }

    /// beat events를 직접 입력받아 측정 BPH를 산출한 뒤 일일 오차로 변환.
    /// - Parameters:
    ///   - beats: 검출된 beat 이벤트 (시간 오름차순)
    ///   - nominalBph: 명목 BPH
    /// - Returns: 일일 오차. beats가 부족하면 nil.
    static func secondsPerDay(beats: [BeatEvent], nominalBph: Int) -> Double? {
        guard beats.count >= 2 else { return nil }
        let first = beats.first!.timestampSeconds
        let last = beats.last!.timestampSeconds
        let duration = last - first
        guard duration > 0 else { return nil }
        // beat 1개 = 3600/BPH 초 → 측정 BPH = 3600 × beats / duration
        // (count - 1)개 inter-onset interval로 정확히 측정
        let measuredBph = 3_600.0 * Double(beats.count - 1) / duration
        return secondsPerDay(measuredBph: measuredBph, nominalBph: nominalBph)
    }
}

```

## `WatchAccuracyPro/Core/DSP/SimplifiedBeatDetector.swift`

```swift
import Accelerate
import Foundation

/// Round 170 (사용자 + 팀 + 전문가 토론 결과): tickIQ-style simplified pipeline.
///
/// 기존 chain: BP → Env → NoiseSupp → Flux → MatchedFilter → BeatDetector → PLL → IOI → OLS/TM
/// 새 chain:   BP → Hilbert env → MAD threshold → parabolic interp → median tight-3%
///
/// 이유 — Müller/Chen 전문가 패널:
/// - Spectral flux 는 5ms 시간 분해능 (200Hz) — rate ±1 s/d 정밀도엔 부적합
/// - NoiseSuppressor 는 정상 tic burst 까지 attenuate 위험
/// - Matched filter 의 template 학습 instability
/// - **Simple = robust**. tickIQ ±5 s/d 의 비결.
enum SimplifiedBeatDetector {

    /// Hilbert analytic signal magnitude — instantaneous envelope.
    /// FFT-based 1-pass. 48kHz × 30s = 1.44M samples → vDSP FFT ~30ms.
    static func hilbertEnvelope(samples: [Float], sampleRate: Double, lpfCutoffHz: Double = 500) -> [Float] {
        let n = samples.count
        guard n > 4 else { return [] }
        // FFT 길이 = 2^ceil(log2(n))
        let log2n = vDSP_Length(ceil(log2(Double(n))))
        let fftN = Int(1 << log2n)

        // Real → complex
        var real = samples + Array(repeating: Float(0), count: fftN - n)
        var imag = [Float](repeating: 0, count: fftN)

        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                // Hilbert filter: H[0] = 1, H[1..N/2-1] = 2, H[N/2] = 1, rest = 0
                // 양의 frequency 만 2배, 음의 frequency 0.
                var zero: Float = 0
                vDSP_vfill(&zero, imagPtr.baseAddress!.advanced(by: fftN/2 + 1), 1, vDSP_Length(fftN/2 - 1))
                vDSP_vfill(&zero, realPtr.baseAddress!.advanced(by: fftN/2 + 1), 1, vDSP_Length(fftN/2 - 1))
                var two: Float = 2
                vDSP_vsmul(realPtr.baseAddress!.advanced(by: 1), 1, &two, realPtr.baseAddress!.advanced(by: 1), 1, vDSP_Length(fftN/2 - 1))
                vDSP_vsmul(imagPtr.baseAddress!.advanced(by: 1), 1, &two, imagPtr.baseAddress!.advanced(by: 1), 1, vDSP_Length(fftN/2 - 1))
                vDSP_fft_zip(setup, &split, 1, log2n, FFTDirection(FFT_INVERSE))
                // Normalize (vDSP inverse 는 N 배 스케일 결과).
                var norm: Float = 1.0 / Float(fftN)
                vDSP_vsmul(realPtr.baseAddress!, 1, &norm, realPtr.baseAddress!, 1, vDSP_Length(fftN))
                vDSP_vsmul(imagPtr.baseAddress!, 1, &norm, imagPtr.baseAddress!, 1, vDSP_Length(fftN))
            }
        }

        // |analytic| = sqrt(real² + imag²)
        var envelope = [Float](repeating: 0, count: n)
        for i in 0..<n {
            envelope[i] = sqrt(real[i] * real[i] + imag[i] * imag[i])
        }
        // 1-pole LPF (RC).
        let dt = 1.0 / sampleRate
        let rc = 1.0 / (2 * .pi * lpfCutoffHz)
        let alpha = Float(dt / (rc + dt))
        var state: Float = 0
        for i in 0..<n {
            state = alpha * envelope[i] + (1 - alpha) * state
            envelope[i] = state
        }
        return envelope
    }

    /// MAD-based adaptive threshold + parabolic interpolation for sub-sample onset times.
    /// - refractoryMs: 검출 후 일정 시간 이내 추가 검출 차단 (sub-pulse 회피).
    /// - kMad: threshold = median + k × 1.4826 × MAD.
    static func detectOnsets(envelope: [Float], sampleRate: Double, refractoryMs: Double = 80, kMad: Float = 3.0) -> [Double] {
        guard envelope.count > 4 else { return [] }
        // Robust threshold via median + MAD
        let sorted = envelope.sorted()
        let median = sorted[sorted.count / 2]
        var absDev = [Float](repeating: 0, count: envelope.count)
        for i in 0..<envelope.count {
            absDev[i] = abs(envelope[i] - median)
        }
        absDev.sort()
        let mad = absDev[absDev.count / 2]
        let threshold = median + kMad * 1.4826 * mad

        let refractorySamples = Int(refractoryMs / 1000.0 * sampleRate)
        var onsets: [Double] = []
        var i = 1
        let n = envelope.count
        while i < n - 1 {
            // Local max above threshold.
            if envelope[i] > threshold && envelope[i] > envelope[i-1] && envelope[i] > envelope[i+1] {
                // Parabolic interpolation for sub-sample precision.
                let y0 = envelope[i-1]
                let y1 = envelope[i]
                let y2 = envelope[i+1]
                let denom = y0 - 2*y1 + y2
                var offset: Float = 0
                if abs(denom) > 1e-9 {
                    offset = 0.5 * (y0 - y2) / denom
                    offset = max(-1, min(1, offset))
                }
                let preciseT = (Double(i) + Double(offset)) / sampleRate
                onsets.append(preciseT)
                i += refractorySamples
            } else {
                i += 1
            }
        }
        return onsets
    }

    /// Median IOI from tight 3% filtered onsets. Returns BPH or nil if insufficient data.
    /// - nominalBph: expected BPH (예: 28800) — IOI tight 필터 기준점.
    static func rateFromOnsets(onsets: [Double], nominalBph: Int) -> (bph: Double, beatCount: Int, residualRMSSeconds: Double)? {
        guard onsets.count >= 8 else { return nil }
        let nominalIOI = 3600.0 / Double(nominalBph)
        var iois: [Double] = []
        for i in 1..<onsets.count {
            iois.append(onsets[i] - onsets[i-1])
        }
        // Tight 5% — sub-pulse 변동 흡수, sample-level outlier 만 제외.
        let tolerance = nominalIOI * 0.05
        let tight = iois.filter { abs($0 - nominalIOI) <= tolerance }
        guard tight.count >= 8 else { return nil }
        let sortedTight = tight.sorted()
        let medianIOI = sortedTight[sortedTight.count / 2]
        // RMS residual of tight IOIs (per-beat).
        let mean = tight.reduce(0, +) / Double(tight.count)
        let variance = tight.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(tight.count)
        let rms = variance.squareRoot()
        return (bph: 3600.0 / medianIOI, beatCount: onsets.count, residualRMSSeconds: rms)
    }
}

```

## `WatchAccuracyPro/Core/DSP/TemplateMatcher.swift`

```swift
import Foundation

/// Round 158: Self-learned template matching — Müller/Wang 패널 권고 구현.
///
/// 동작:
/// 1. 첫 N 개 clean onset 의 envelope 주변 ±halfWindowMs 추출
/// 2. Average → tic 의 acoustic signature template
/// 3. 후속 onset: 예상 시점 ±searchWindowMs 안에서 template cross-correlation
/// 4. Correlation peak 위치 = sub-sample precise timestamp
///
/// 결과: onset detection 의 ±23ms 오차가 sub-millisecond 로 향상.
final class TemplateMatcher {
    private(set) var template: [Float] = []
    private let halfWindowSamples: Int
    private let sampleRate: Double

    init(sampleRate: Double = 48_000, halfWindowMs: Double = 10) {
        self.sampleRate = sampleRate
        self.halfWindowSamples = Int(halfWindowMs / 1000.0 * sampleRate)
    }

    /// 학습 — 클린 onset 들의 envelope 평균을 template 으로.
    func learn(envelope: [Float], onsets: [BeatEvent]) {
        guard !onsets.isEmpty, envelope.count > 2 * halfWindowSamples else {
            template = []
            return
        }
        var accumulator = [Float](repeating: 0, count: 2 * halfWindowSamples + 1)
        var count = 0
        for beat in onsets {
            let centerIdx = Int(beat.timestampSeconds * sampleRate)
            let lo = centerIdx - halfWindowSamples
            let hi = centerIdx + halfWindowSamples
            guard lo >= 0, hi < envelope.count else { continue }
            for i in 0...(2 * halfWindowSamples) {
                accumulator[i] += envelope[lo + i]
            }
            count += 1
        }
        guard count > 0 else {
            template = []
            return
        }
        let inv = Float(1.0 / Double(count))
        template = accumulator.map { $0 * inv }
        // Normalize — L2 norm 1.
        var sumSq: Float = 0
        for v in template { sumSq += v * v }
        let norm = sqrt(sumSq)
        if norm > 0 {
            for i in 0..<template.count { template[i] /= norm }
        }
    }

    /// 예상 시점 주변에서 template cross-correlation peak 위치 반환 (seconds).
    /// peak 못 찾으면 expectedTime 그대로 반환.
    func refinePeakTime(envelope: [Float], expectedTime: Double, searchWindowMs: Double = 15) -> Double {
        guard !template.isEmpty, !envelope.isEmpty else { return expectedTime }
        let searchSamples = Int(searchWindowMs / 1000.0 * sampleRate)
        let centerIdx = Int(expectedTime * sampleRate)
        let lo = max(halfWindowSamples, centerIdx - searchSamples)
        let hi = min(envelope.count - halfWindowSamples - 1, centerIdx + searchSamples)
        guard lo < hi else { return expectedTime }
        var maxCorr: Float = -.infinity
        var maxIdx = lo
        for i in lo...hi {
            var corr: Float = 0
            for k in 0..<template.count {
                corr += envelope[i - halfWindowSamples + k] * template[k]
            }
            if corr > maxCorr {
                maxCorr = corr
                maxIdx = i
            }
        }
        // Parabolic interp — sub-sample precision.
        let preciseIdx: Double
        if maxIdx > lo && maxIdx < hi {
            // Compute 3-point parabola.
            func corrAt(_ i: Int) -> Float {
                var c: Float = 0
                for k in 0..<template.count {
                    c += envelope[i - halfWindowSamples + k] * template[k]
                }
                return c
            }
            let yL = corrAt(maxIdx - 1)
            let yC = maxCorr
            let yR = corrAt(maxIdx + 1)
            let denom = yL - 2 * yC + yR
            let delta: Double = denom != 0 ? Double(0.5 * (yL - yR) / denom) : 0
            preciseIdx = Double(maxIdx) + max(-1, min(1, delta))
        } else {
            preciseIdx = Double(maxIdx)
        }
        return preciseIdx / sampleRate
    }
}

```
