import Foundation
import SwiftData
import AVFoundation
import UIKit
import WidgetKit

@Observable
final class MeasurementViewModel {
    enum State: Equatable {
        case idle
        case requestingPermission
        case measuring
        /// Round 158: 측정 종료 후 분석 진행 중 (PLL+Template 처리). 사용자에게 "분석 중..." 표시.
        case analyzing
        case completed(MeasurementResult)
        case failed(FailureReason)
    }

    enum FailureReason: String, Equatable {
        /// 마이크 권한이 거부됨.
        case permissionDenied
        /// 측정 시간이 너무 짧아 분석 불가 (envelope < 0.5s).
        case tooShort
        /// 0.5s 이상이지만 BPH lock / beat detection 실패 — 신호가 약하거나 노이즈.
        case noSignal
        /// 오디오 엔진 시작 실패 (마이크 충돌, BT 라우팅 등).
        case audioEngineFailure
        /// Round 98 (QA Critical): quartz / 미지원 무브먼트 — 측정 시도 자체 차단.
        case unsupportedMovement
        /// Round 98 (DSP Critical): BPH lock 은 잡혔으나 rate/beatError 가 anomaly 범위 — 망가진 시계 OR lock 실패.
        case lockFailure
    }

    private(set) var state: State = .idle
    private(set) var liveMetrics: LiveMetrics = .init(confidenceScore: 0, elapsedSeconds: 0)
    /// Round 170 (디버깅): persist 실패 시 마지막 거부 result + 사유 코드 보존 → 화면에 노출.
    private(set) var lastRejectedResult: MeasurementResult? = nil
    private(set) var lastRejectionReason: String? = nil
    /// 라이브 wave 표시용 — 최근 200개 다운샘플된 진폭 (-1...1).
    private(set) var waveformSamples: [Float] = Array(repeating: 0, count: 200)
    /// 페르소나 (김재철) wish: position picker. 측정 전 사용자가 자세 선택.
    var selectedPosition: Position = .unknown

    /// 측정 중 마지막 LiveMetrics 의 SNR (dB). 마이크 위치 힌트용.
    var lastSnapshotSNRDB: Double? { liveMetrics.snrDB }

    /// 측정 시작 시각 — UI 의 timeline 기반 elapsed 계산용.
    /// analyzer cycle 과 무관하게 매 프레임 부드럽게 시간 표시.
    private(set) var measurementStartedAt: Date?

    /// Round 95 (이형준 Critical #1): 측정 시작 시 NTP offset 한 번 fetch — 디바이스 시계 drift 보정용.
    /// 측정에 wall-clock 차이를 적용하지는 않지만 (측정 자체는 audio sample rate 기반), persistence 시
    /// metadata 에 기록해 추후 device-clock 분석 신뢰도 평가 가능.
    private(set) var ntpOffsetMs: Double?

    let watch: Watch
    let movement: Movement?
    let preferences: UserPreferences

    /// 테스트/preview 에서 합성 신호를 주입할 때 사용. 프로덕션에서는 nil 이라 `AudioCapture` 가 쓰임.
    private let audioSourceOverride: AudioSource?

    private var pipeline: DSPPipeline?
    private var captureSource: AudioSource?
    private var metricsTask: Task<Void, Never>?
    private var waveformTask: Task<Void, Never>?

    init(watch: Watch, preferences: UserPreferences, audioSourceOverride: AudioSource? = nil) {
        self.watch = watch
        self.preferences = preferences
        self.audioSourceOverride = audioSourceOverride
        if let caliber = watch.caliber {
            self.movement = MovementDatabase.shared.movement(id: caliber)
        } else {
            self.movement = nil
        }
    }

    deinit {
        metricsTask?.cancel()
        waveformTask?.cancel()
        _ = pipeline?.stop()
    }

    @MainActor
    func start() async {
        state = .requestingPermission
        let granted = await requestMicrophonePermission()
        guard granted else {
            state = .failed(.permissionDenied)
            return
        }
        // Round 98 (QA Critical C2): quartz / bph=0 무브먼트는 마이크 BPH 측정 불가 — 즉시 거부.
        // Round 100 (김수아 C2): caliber nil 인 경우에도 Watch.movementType 으로 quartz 차단.
        // silicon escapement 는 동작상 swiss lever 와 동일하므로 통과 시킨다.
        let isQuartzByMovement = movement.map { $0.escapement == .quartz || $0.bph <= 0 } ?? false
        let isQuartzByWatch = watch.movementType == .quartz
        if isQuartzByMovement || isQuartzByWatch {
            state = .failed(.unsupportedMovement)
            return
        }
        do {
            // Round 170 (사용자 보고: 처음 측정 시작 시 1-2초 옛날 그래프 나옴):
            // 이전 측정의 waveformSamples 가 남아 있음 → 새 측정 시 초기화.
            waveformSamples = Array(repeating: 0, count: waveformSamples.count)
            liveMetrics = .init(confidenceScore: 0, elapsedSeconds: 0)
            lastRejectedResult = nil
            lastRejectionReason = nil
            setKeepScreenOn(enabled: preferences.keepScreenOnDuringMeasurement)
            let nominalBph = watch.customBph ?? movement?.bph ?? 28_800
            // 페르소나 (김재철) wish: watch-level lift angle override 가 있으면 우선.
            let liftAngle = watch.liftAngleOverride ?? movement?.liftAngleDegrees
            let escapement = movement?.escapement ?? .swissLever
            let reliability = movement?.confidenceLabel ?? .high
            let source: AudioSource = audioSourceOverride ?? AudioCapture()
            captureSource = source
            let pipeline = DSPPipeline(
                source: source,
                nominalBph: nominalBph,
                liftAngleDegrees: liftAngle,
                escapement: escapement,
                reliabilityLabel: reliability,
                useSimplified: preferences.useSimplifiedDSP
            )
            self.pipeline = pipeline

            let metricsStream = pipeline.liveMetricsStream
            metricsTask = Task { [weak self] in
                for await live in metricsStream {
                    await MainActor.run {
                        self?.liveMetrics = live
                        if #available(iOS 16.2, *) {
                            MeasurementLiveActivityService.shared.update(with: live)
                        }
                    }
                }
            }
            if #available(iOS 16.2, *) {
                MeasurementLiveActivityService.shared.start(
                    watchName: "\(watch.brand) \(watch.model)",
                    caliber: movement?.id
                )
            }

            let waveformStream = pipeline.liveWaveformStream
            waveformTask = Task { [weak self] in
                for await chunk in waveformStream {
                    await MainActor.run { self?.applyWaveform(chunk: chunk) }
                }
            }

            try pipeline.start()
            measurementStartedAt = Date()
            state = .measuring
            // Round 140 (H1): 측정 진행 중 notification — RootTabView 가 epoch reset 차단.
            NotificationCenter.default.post(name: .ticklabMeasurementDidStart, object: nil)

            // Round 95: NTP fire-and-forget — 측정 종료 전까지 도착하면 metadata 에 기록.
            // 실패해도 측정엔 영향 없음 (device clock 기반 보강용).
            Task { [weak self] in
                guard let sample = try? await AtomicTimeService.shared.fetchSample() else { return }
                await MainActor.run {
                    self?.ntpOffsetMs = sample.offsetSeconds * 1000.0
                }
            }
        } catch {
            state = .failed(.audioEngineFailure)
        }
    }

    /// 새 chunk 의 다운샘플 결과를 ring 처럼 누적해 항상 200개 길이를 유지.
    @MainActor
    private func applyWaveform(chunk: LiveWaveformChunk) {
        let target = waveformSamples.count
        guard target > 0 else { return }
        let appended = waveformSamples + chunk.samples
        if appended.count <= target {
            waveformSamples = Array(repeating: 0, count: target - appended.count) + appended
        } else {
            waveformSamples = Array(appended.suffix(target))
        }
    }

    @MainActor
    func stop(modelContext: ModelContext) {
        // Round 78: race guard — 30s wall-clock auto-stop 과 manual stop 동시 호출 방지.
        guard case .measuring = state else { return }
        // Round 158 (사용자 보고: 30s 후에도 측정 계속하는 듯 보임):
        // state 를 .analyzing 으로 즉시 전환 → 타이머 멈춤, UI "분석 중" 표시 가능.
        state = .analyzing
        // Stop UX 수정 (사용자 보고): UI 가 즉시 반응하도록 background 로 분석 분리.
        // 1) 즉시 task 취소 + audio 정지
        metricsTask?.cancel()
        waveformTask?.cancel()
        let pipelineRef = pipeline
        setKeepScreenOn(enabled: false)
        if #available(iOS 16.2, *) {
            MeasurementLiveActivityService.shared.end(final: liveMetrics)
        }
        // Round 141 (Hyemi H7): didEnd notification 을 분석 background task 의 main 도착 후로 옮김.
        // 분석 중 사용자가 탭 전환하면 결과 화면 진입 못 함 → 결과 표시 후 epoch reset 허용.
        // 2) 분석은 background 에서 — UI 는 즉시 dismiss-able 상태로 전환
        // Round 170 (사용자 보고: 재측정 시 렉): pipeline 즉시 nil 처리 →
        // 이후 cancel() 이 pipeline?.stop() 으로 analyze() 재실행하는 사고 차단.
        let elapsed = liveMetrics.elapsedSeconds
        pipeline = nil
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = pipelineRef?.stop()
            await MainActor.run {
                guard let self else {
                    // self deinit 됐어도 RootTabView 보호 해제는 해야 함.
                    NotificationCenter.default.post(name: .ticklabMeasurementDidEnd, object: nil)
                    return
                }
                if let result {
                    // Round 169: anomaly 면 .completed 가 아닌 .failed 로 → 사용자에게 명확히 알림.
                    // Round 100: anomaly trip 은 .lockFailure 로 분기 (BPH lock 잡혔으나 신뢰 X).
                    if self.persist(result: result, in: modelContext) {
                        self.state = .completed(result)
                    } else {
                        self.state = .failed(.lockFailure)
                    }
                } else {
                    // Round 89 (김재철 Critical): tooShort 임계 1.0→0.5 — 실 4-5초 측정 SNR 약한 신호 진단 정보 손실 방지.
                    self.state = .failed(elapsed < 0.5 ? .tooShort : .noSignal)
                }
                // Round 141 (Hyemi H7): 결과 표시 state 설정 후 RootTabView 보호 해제.
                NotificationCenter.default.post(name: .ticklabMeasurementDidEnd, object: nil)
            }
        }
    }

    /// 사용자가 측정 화면을 떠날 때 호출 (취소). state 를 idle 로 되돌리고 결과는 저장 안 함.
    /// Round 158 (사용자 보고: 재측정 누르면 다른 화면 이동/렉/멈춤):
    /// 기존 early return 이 state .idle 리셋 누락 → navigationDestination(item:) 재발화 → 화면 재진입.
    /// 모든 경우에 state .idle 리셋 + cleanup 보장.
    @MainActor
    func cancel() {
        _ = pipeline?.stop()
        pipeline = nil
        metricsTask?.cancel()
        waveformTask?.cancel()
        setKeepScreenOn(enabled: false)
        if #available(iOS 16.2, *) {
            MeasurementLiveActivityService.shared.end(final: nil)
        }
        // 모든 경우에 state 리셋 — navigationDestination(item:) 재발화 차단 (재측정 흐름 정상화).
        state = .idle
        NotificationCenter.default.post(name: .ticklabMeasurementDidEnd, object: nil)
    }

    /// Round 169: 반환 Bool — false 면 stop() 이 state=.failed(.noSignal) 로 전환해 사용자에게 알림.
    @discardableResult
    private func persist(result: MeasurementResult, in context: ModelContext) -> Bool {
        // Round 158 (Jay #F6): persist filter 대폭 완화. 거부 자체가 사용자에게 학습 효과 0 (Round 156-157
        // 효과 검증 차단). reliabilityGrade (A/B/C/F) 가 이미 사용자에게 신뢰도 표시 — persist 는 *명확한*
        // garbage (BPH lock 완전 실패) 만 차단.
        //   |rate| <= 300 + conf >= 10 + beatError <= 50 → 통과 (grade 가 사용자에게 신뢰도 알림)
        //   그 외 → 거부 (lock 자체가 실패한 경우)
        let absRate = abs(result.rateSecondsPerDay)
        // Round 170 (사용자 보고: -67.5 s/d / 73 beats / 0.20ms beat error 가 결과로 표시됨):
        // 73 beats 는 30s 측정에서 기대치 (~240 beats @ 28800 BPH) 의 30% — 대부분 tic 누락.
        // 누락이 많으면 median IOI 가 가짜 peak (e.g., 매 3 beat 만 잡힘 → IOI 3× too long).
        // 최소 beat count 게이트 추가: expected = duration × BPH/3600. 50% 미만이면 거부.
        let expectedBeats = max(1, Int(Double(result.durationSeconds) * Double(result.bph) / 3600.0))
        let beatYield = Double(result.beatCount) / Double(expectedBeats)
        // Round 170 (팀 토론 결과 — Jay/Min/Hyemi/Doyoon 합의):
        // 1) beat error ≤ 1.5ms — cleanedBeats 기준 metric (IOI-filter 후 잡음 제거됨).
        // 2) OLS residual RMS ≤ 50μs — rate 정밀도 직접 게이트. 240 beats 면 ±2 s/d 보장.
        // 둘 다 AND 게이트로 → 사용자 UI 친화 + 실제 정확도 spec 동시 만족.
        // Round 170 (재계산): 게이트를 raw RMS → OLS slope uncertainty 기반 rate 정밀도로 전환.
        // OLS 이론: σ_slope = σ_resid × √12 / N^1.5  (균등 분포 index)
        // rate uncertainty (s/day) = σ_slope / nominalPeriod × 86400
        // 사용자 목표 ±1 s/d → 게이트 ≤ 2 s/d (안전마진 2×).
        let rateUncertaintySD: Double = {
            guard let rms = result.residualRMSSeconds, result.beatCount > 1 else { return .infinity }
            let n = Double(result.beatCount)
            let nominalPeriod = 3600.0 / Double(result.bph)
            let sigmaSlope = rms * 12.0.squareRoot() / pow(n, 1.5)
            return sigmaSlope / nominalPeriod * 86400.0
        }()
        var failedGates: [String] = []
        if absRate > 300 { failedGates.append("rate>300") }
        if result.confidenceScore < 10 { failedGates.append("conf<10") }
        if result.beatErrorMs > 1.5 { failedGates.append("박동오차>1.5ms") }
        if rateUncertaintySD > 2.0 { failedGates.append(String(format: "rate정밀도>±2s/d(%.1f)", rateUncertaintySD)) }
        if beatYield < 0.5 { failedGates.append("beatYield<50%") }
        guard failedGates.isEmpty else {
            #if DEBUG
            let rmsString = result.residualRMSSeconds.map { String(format: "%.1fμs", $0 * 1_000_000) } ?? "nil"
            print("⚠️ Refusing to persist: failed=\(failedGates) " +
                  "rate=\(result.rateSecondsPerDay), beatError=\(result.beatErrorMs), " +
                  "rms=\(rmsString), conf=\(result.confidenceScore), " +
                  "beats=\(result.beatCount)/\(expectedBeats) (\(Int(beatYield * 100))%)")
            #endif
            lastRejectedResult = result
            lastRejectionReason = failedGates.joined(separator: ", ")
            return false
        }
        // Round 158 (사용자 보고: F-grade 측정도 저장되어 트렌드 오염):
        // F-grade 는 알고리즘이 "신뢰 부족" 으로 판단 — 저장 안 함, 사용자 재측정 유도.
        if result.reliabilityGrade == .f {
            #if DEBUG
            print("⚠️ F-grade measurement not persisted (low reliability — encouraging retry)")
            #endif
            lastRejectedResult = result
            lastRejectionReason = "F-grade"
            return false
        }
        // success — clear prior rejection info
        lastRejectedResult = nil
        lastRejectionReason = nil
        // Round 168: 측정 성공 → mood 캐시 무효화.
        WatchMoodService.invalidate(for: watch)
        // Round 18 (Doyoon): SNR 을 ambientNoiseDB 에 잘못 저장하던 history 와 호환 위해 양쪽 field 모두 채움.
        //   장기적으로는 ambientNoiseDB 는 별도 추정치로 분리하고 snrDB 만 의미적 진실로 보존.
        let metadata = MeasurementMetadata(
            position: selectedPosition,
            ambientNoiseDB: result.snrDB,
            snrDB: result.snrDB,
            deviceModel: deviceModelString(),
            microphoneType: AudioInputManager.shared.activeMicrophoneType,
            ntpOffsetMs: ntpOffsetMs
        )
        let measurement = WatchMeasurement(
            rateSecondsPerDay: result.rateSecondsPerDay,
            beatErrorMs: result.beatErrorMs,
            amplitudeDegrees: result.amplitudeDegrees,
            bph: result.bph,
            confidenceScore: result.confidenceScore,
            durationSeconds: result.durationSeconds,
            metadata: metadata
        )
        context.insert(measurement)
        measurement.watch = watch
        try? context.save()

        // 위젯 / 잠금화면용 스냅샷 갱신.
        let snapshot = LatestMeasurementSnapshot(
            watchName: "\(watch.brand) \(watch.model)",
            caliber: movement?.id,
            timestamp: measurement.timestamp,
            rateSecondsPerDay: result.rateSecondsPerDay,
            beatErrorMs: result.beatErrorMs,
            amplitudeDegrees: result.amplitudeDegrees,
            bph: result.bph,
            confidenceScore: result.confidenceScore
        )
        SharedSnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        return true
    }

    private func requestMicrophonePermission() async -> Bool {
        if #available(iOS 17.0, *) {
            await AVAudioApplication.requestRecordPermission()
        } else {
            await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }
    }

    private func setKeepScreenOn(enabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = enabled
    }

    private func deviceModelString() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}
