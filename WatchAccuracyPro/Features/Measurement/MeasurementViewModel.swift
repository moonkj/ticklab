import Foundation
import SwiftData
import AVFoundation
import UIKit

@Observable
final class MeasurementViewModel {
    enum State: Equatable {
        case idle
        case requestingPermission
        case measuring
        case completed(MeasurementResult)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var liveMetrics: LiveMetrics = .init(confidenceScore: 0, elapsedSeconds: 0)
    /// 라이브 wave 표시용 — 최근 200개 다운샘플된 진폭 (-1...1).
    private(set) var waveformSamples: [Float] = Array(repeating: 0, count: 200)

    let watch: Watch
    let movement: Movement?
    let preferences: UserPreferences

    private var pipeline: DSPPipeline?
    private var captureSource: AudioCapture?
    private var lastWaveformPushAt = Date.distantPast
    private var streamTask: Task<Void, Never>?

    init(watch: Watch, preferences: UserPreferences) {
        self.watch = watch
        self.preferences = preferences
        if let caliber = watch.caliber {
            self.movement = MovementDatabase.shared.movement(id: caliber)
        } else {
            self.movement = nil
        }
    }

    deinit {
        streamTask?.cancel()
        pipeline?.stop()
    }

    @MainActor
    func start() async {
        state = .requestingPermission
        let granted = await requestMicrophonePermission()
        guard granted else {
            state = .failed("permission")
            return
        }
        do {
            applySilentMode(enabled: preferences.silentModeDefault)
            let nominalBph = movement?.bph ?? 28_800
            let liftAngle = movement?.liftAngleDegrees
            let escapement = movement?.escapement ?? .swissLever
            let reliability = movement?.confidenceLabel ?? .high
            let source = AudioCapture()
            captureSource = source
            let pipeline = DSPPipeline(
                source: source,
                nominalBph: nominalBph,
                liftAngleDegrees: liftAngle,
                escapement: escapement,
                reliabilityLabel: reliability
            )
            self.pipeline = pipeline

            streamTask = Task { [weak self] in
                guard let stream = self?.pipeline?.liveMetricsStream else { return }
                for await live in stream {
                    await MainActor.run { self?.liveMetrics = live }
                }
            }

            try pipeline.start()
            state = .measuring
        } catch {
            state = .failed("\(error)")
        }
    }

    @MainActor
    func stop(modelContext: ModelContext) {
        guard case .measuring = state else { return }
        let result = pipeline?.stop()
        streamTask?.cancel()
        applySilentMode(enabled: false)

        if let result {
            persist(result: result, in: modelContext)
            state = .completed(result)
        } else {
            state = .failed("noresult")
        }
    }

    private func persist(result: MeasurementResult, in context: ModelContext) {
        let metadata = MeasurementMetadata(
            position: .unknown,
            ambientNoiseDB: result.snrDB,
            deviceModel: deviceModelString(),
            microphoneType: .builtin
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

    private func applySilentMode(enabled: Bool) {
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
