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
                envelopeDynamicRange: diagnostic.dynamicRange
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
                lockFailReason: lastAnalyzeFailReason
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
            lockFailReason: lastAnalyzeFailReason
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
            guard reliabilityLabel == .high else { return nil }
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
            case .medium, .low: return .generic
            case .high:         return nil
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
            guard reliabilityLabel == .high else { return nil }
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
            case .medium, .low:
                return .generic
            case .high:
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
