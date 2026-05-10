import Accelerate
import Foundation

/// AudioSource 의 샘플 스트림을 받아 envelope·beat 검출·메트릭 분석까지 수행.
/// 라이브 메트릭은 `liveMetricsStream` 으로, 스냅샷 결과는 `analyze(...)` 로 노출.
final class DSPPipeline {
    private let source: AudioSource
    private let nominalBph: Int
    private let liftAngleDegrees: Double?
    private let escapement: Escapement
    private let reliabilityLabel: ReliabilityLabel

    private let preEmphasis = PreEmphasisFilter()
    private let bandPass: BandPassFilter
    private let envelopeExtractor: EnvelopeExtractor

    private var rawBuffer: [Float] = []
    private var envelopeBuffer: [Float] = []
    private var startTime: Date?
    private var continuation: AsyncStream<LiveMetrics>.Continuation?
    private(set) var lastSnapshot: MeasurementResult?

    /// 라이브 메트릭 스트림 (UI 가 0.5~1초 주기로 갱신).
    let liveMetricsStream: AsyncStream<LiveMetrics>

    init(
        source: AudioSource,
        nominalBph: Int,
        liftAngleDegrees: Double?,
        escapement: Escapement,
        reliabilityLabel: ReliabilityLabel
    ) {
        self.source = source
        self.nominalBph = nominalBph
        self.liftAngleDegrees = liftAngleDegrees
        self.escapement = escapement
        self.reliabilityLabel = reliabilityLabel
        self.bandPass = BandPassFilter(sampleRate: source.sampleRate)
        self.envelopeExtractor = EnvelopeExtractor(sampleRate: source.sampleRate)

        var continuation: AsyncStream<LiveMetrics>.Continuation!
        self.liveMetricsStream = AsyncStream { c in continuation = c }
        self.continuation = continuation
    }

    func start() throws {
        startTime = Date()
        rawBuffer.removeAll(keepingCapacity: true)
        envelopeBuffer.removeAll(keepingCapacity: true)
        preEmphasis.reset()
        bandPass.reset()
        envelopeExtractor.reset()
        lastSnapshot = nil

        try source.start { [weak self] samples in
            self?.process(chunk: samples)
        }
    }

    func stop() -> MeasurementResult? {
        source.stop()
        let result = analyze()
        lastSnapshot = result
        continuation?.finish()
        return result
    }

    private func process(chunk: [Float]) {
        // 누적 (raw 는 SNR 계산용, envelope 은 분석용)
        rawBuffer.append(contentsOf: chunk)
        let pre = preEmphasis.process(chunk)
        let bp = bandPass.process(pre)
        let env = envelopeExtractor.process(bp)
        envelopeBuffer.append(contentsOf: env)

        // 0.5초마다 라이브 메트릭 emit
        let elapsed = Date().timeIntervalSince(startTime ?? Date())
        if envelopeBuffer.count >= Int(source.sampleRate * 0.5),
           Int(elapsed * 2) % 1 == 0 {
            let live = liveMetrics(elapsed: elapsed)
            continuation?.yield(live)
        }
    }

    /// 현재까지 수집된 데이터로 분석한 스냅샷을 반환.
    func analyze() -> MeasurementResult? {
        guard envelopeBuffer.count > Int(source.sampleRate * 0.5) else { return nil }
        guard let bphEstimate = BPHEstimator.estimate(envelope: envelopeBuffer, sampleRate: source.sampleRate) else {
            return nil
        }
        let beats = BeatDetector.detectOnsets(envelope: envelopeBuffer, sampleRate: source.sampleRate)
        let elapsed = Date().timeIntervalSince(startTime ?? Date())
        let rate = RateCalculator.secondsPerDay(measuredBph: bphEstimate.rawBph, nominalBph: nominalBph)
        let beatErrorMs = BeatErrorCalculator.beatErrorMs(beats: beats) ?? 0
        let snr = estimateSNR()

        let amplitude: Double? = {
            guard reliabilityLabel == .high else { return nil }
            return AmplitudeEstimator.estimate(
                envelope: envelopeBuffer,
                beats: beats,
                sampleRate: source.sampleRate,
                liftAngleDegrees: liftAngleDegrees,
                escapement: escapement
            )
        }()

        let confidence = ConfidenceScorer.score(.init(
            snrDB: snr,
            durationSeconds: elapsed,
            bphAutocorrelationConfidence: bphEstimate.confidence,
            beatCount: beats.count,
            beatErrorMs: beatErrorMs
        ))

        let reliabilityKey: String? = {
            switch reliabilityLabel {
            case .medium where escapement == .coAxial:
                return "movement.reliability.coaxial.notice"
            case .medium, .low:
                return "movement.reliability.generic.notice"
            case .high:
                return nil
            }
        }()

        return MeasurementResult(
            bph: bphEstimate.bph,
            rateSecondsPerDay: rate,
            beatErrorMs: beatErrorMs,
            amplitudeDegrees: amplitude,
            confidenceScore: confidence,
            durationSeconds: Int(elapsed.rounded()),
            snrDB: snr,
            beatCount: beats.count,
            reliabilityNoteKey: reliabilityKey
        )
    }

    private func liveMetrics(elapsed: Double) -> LiveMetrics {
        let snapshot = analyze()
        return LiveMetrics(
            bph: snapshot?.bph,
            rateSecondsPerDay: snapshot?.rateSecondsPerDay,
            beatErrorMs: snapshot?.beatErrorMs,
            amplitudeDegrees: snapshot?.amplitudeDegrees,
            confidenceScore: snapshot?.confidenceScore ?? 0,
            elapsedSeconds: elapsed
        )
    }

    /// rawBuffer 의 RMS 와 envelope 의 베이스라인 차이로 SNR을 추정.
    private func estimateSNR() -> Double {
        guard !rawBuffer.isEmpty, !envelopeBuffer.isEmpty else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(rawBuffer, 1, &rms, vDSP_Length(rawBuffer.count))
        var noiseFloor: Float = 0
        // envelope의 하위 10퍼센타일을 noise floor로 추정
        let sorted = envelopeBuffer.sorted()
        let p10Idx = max(0, sorted.count / 10)
        noiseFloor = sorted[p10Idx]
        guard noiseFloor > 0 else { return 60 }
        let ratio = Double(rms) / Double(noiseFloor)
        return 20 * log10(max(ratio, 1))
    }
}
