import Foundation
import AVFoundation

// MARK: - FastRatePipeline
// 기존 DSPPipeline의 30초 autocorrelation을 대체하는 고속 파이프라인 제안.
//   BPH known(MovementDB) → 즉시 IOI 수집 → 수렴 시 종료
//   BPH unknown            → 1초 Goertzel 추정 → IOI 수집 → 수렴 시 종료
// 기존 DSPPipeline은 미등록 캘리버 fallback으로 유지. MeasurementViewModel에서 분기.
// (제안 — 미통합. 검토용 보관. ⚠️ onset 시각 50ms 청크 양자화·median-IOI 위상편향 — 리뷰 포인트.)

struct FastRateResult {
    let rateSecPerDay: Double
    let beatErrorMs: Double?
    let confidenceScore: Int         // 0~100
    let measurementDuration: Double
    let bph: Int
    let method: Method

    enum Method {
        case fastIOIKalman
        case legacyAutocorr
    }
}

final class FastRatePipeline {

    // MARK: - Timing constants
    static let minimumDuration: Double = 3.0
    static let maximumDuration: Double = 15.0
    private static let goertzelBufferSecs: Double = 1.2

    // MARK: - Dependencies
    private let audioSource: any AudioSource
    private let movementDatabase: MovementDatabase

    // MARK: - DSP chain components
    private let preEmphasis = PreEmphasisFilter()
    private var bandPass: BandPassFilter
    private let envelopeExtractor = EnvelopeExtractor()
    private var onsetDetector: AdaptiveOnsetDetector
    private var rateEstimator: IOIRateEstimator

    private var goertzelBuffer: [Float] = []
    private let samplesPerChunk: Int

    // MARK: - State
    private var bph: Int
    private var bphIsKnown: Bool
    private var phase: Phase = .warmingUp

    private enum Phase {
        case warmingUp
        case collecting
    }

    // MARK: - Init
    init(
        audioSource: any AudioSource = AudioCapture(),
        watch: Watch,
        movementDatabase: MovementDatabase
    ) {
        self.audioSource = audioSource
        self.movementDatabase = movementDatabase

        if let movement = movementDatabase.bestMatch(for: watch),
           movement.bph > 0 {
            self.bph = movement.bph
            self.bphIsKnown = true
            self.phase = .collecting
        } else {
            self.bph = 28800
            self.bphIsKnown = false
            self.phase = .warmingUp
        }

        let centerHz = Double(self.bph) / 7200.0
        self.bandPass = BandPassFilter(centerHz: centerHz, qFactor: 5.0)

        let chunkDuration = 0.05
        self.samplesPerChunk = Int(48_000 * chunkDuration)
        self.onsetDetector = AdaptiveOnsetDetector(bph: self.bph, chunkDuration: chunkDuration)
        self.rateEstimator = IOIRateEstimator()
        self.rateEstimator.nominalBPH = self.bph
    }

    // MARK: - Measurement
    func measure() async throws -> FastRateResult {
        let startTime = Date()
        var chunkIndex = 0

        goertzelBuffer.removeAll()
        onsetDetector.reset()
        rateEstimator.reset()

        for await chunk in audioSource.chunks {
            let elapsed = Date().timeIntervalSince(startTime)

            let preEmph = preEmphasis.process(chunk)
            let filtered = bandPass.process(preEmph)
            let envPeak = envelopeExtractor.peakAmplitude(filtered)

            switch phase {
            case .warmingUp:
                goertzelBuffer.append(contentsOf: filtered)
                let neededSamples = Int(48_000 * FastRatePipeline.goertzelBufferSecs)
                guard goertzelBuffer.count >= neededSamples else { break }

                if let estimate = BPHEstimator.goertzelEstimate(
                    envelopeSamples: goertzelBuffer,
                    sampleRate: 48_000,
                    minDuration: FastRatePipeline.goertzelBufferSecs
                ) {
                    reconfigure(bph: estimate.bph)
                } else {
                    reconfigure(bph: bph)
                }
                phase = .collecting

            case .collecting:
                if let onsetTime = onsetDetector.process(envelopePeak: envPeak) {
                    rateEstimator.addOnset(time: onsetTime, parity: onsetDetector.beatParity)
                }
                if elapsed >= FastRatePipeline.minimumDuration && rateEstimator.isConverged {
                    break
                }
            }

            if elapsed >= FastRatePipeline.maximumDuration { break }
            chunkIndex += 1
        }

        let duration = Date().timeIntervalSince(startTime)
        return FastRateResult(
            rateSecPerDay: rateEstimator.rateSecPerDay,
            beatErrorMs: rateEstimator.beatErrorMs,
            confidenceScore: rateEstimator.confidenceScore,
            measurementDuration: duration,
            bph: bph,
            method: .fastIOIKalman
        )
    }

    // MARK: - Reconfigure after BPH determination
    private func reconfigure(bph newBPH: Int) {
        bph = newBPH
        let centerHz = Double(newBPH) / 7200.0
        bandPass = BandPassFilter(centerHz: centerHz, qFactor: 5.0)
        onsetDetector = AdaptiveOnsetDetector(bph: newBPH, chunkDuration: 0.05)
        rateEstimator = IOIRateEstimator()
        rateEstimator.nominalBPH = newBPH
        for sample in goertzelBuffer.chunks(ofSize: samplesPerChunk) {
            let envPeak = envelopeExtractor.peakAmplitude(sample)
            if let t = onsetDetector.process(envelopePeak: envPeak) {
                rateEstimator.addOnset(time: t, parity: onsetDetector.beatParity)
            }
        }
    }
}

// MARK: - Array chunk helper (내부용)
private extension Array {
    func chunks(ofSize size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
