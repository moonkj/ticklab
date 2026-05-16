import SwiftData
import SwiftUI

struct MeasurementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(UserPreferences.self) private var preferences
    @State private var viewModel: MeasurementViewModel
    @State private var showDailyLimitAlert = false
    /// shell-level paywall.
    @Environment(\.purchaseRouter) private var purchaseRouter
    /// 사용자 보고 fix: @Query allMeasurements 전체 fetch 후 body 마다 startOfDay 필터링 → 200+ 측정 시
    ///   매 render scan. predicate fetch + onAppear/완료시 refresh 로 변경.
    @State private var todayMeasurementCount: Int = 0

    // Round 158: 30s 로 복귀 — drift 영향 시간 줄여 정확도 향상 시도.
    private let recommendedSeconds: Double = 30

    /// Round 161: state == .measuring 을 task(id:) 키로 사용해 wall-clock 자동 stop.
    private var stateIsMeasuring: Bool {
        if case .measuring = viewModel.state { return true }
        return false
    }

    /// SNR hint hysteresis — 깜빡임 방지. 4초 연속 SNR < 12 일 때만 "약 신호" 경고.
    @State private var weakSnrSeenAt: Date?
    /// 사용자 보고: 풀와인딩 안 한 시계 -45 s/d → "측정 오류" 오해. 측정 시작 전 안내 토스트.
    @State private var showWindingHint: Bool = false

    init(watch: Watch, preferences: UserPreferences) {
        _viewModel = State(wrappedValue: MeasurementViewModel(watch: watch, preferences: preferences))
    }

    /// 사용자 결정: Free 사용자는 하루 3회 측정 제한. Pro 무제한.
    private var canStartMeasurement: Bool {
        guard !preferences.isPro else { return true }
        return todayMeasurementCount < ProEntitlement.freeDailyMeasurementLimit
    }

    /// 오늘 측정 카운트 — startOfDay >= 인 WatchMeasurement 개수만 fetch.
    private func refreshTodayMeasurementCount() {
        guard !preferences.isPro else { return }
        let todayStart = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<WatchMeasurement>(
            predicate: #Predicate { $0.timestamp >= todayStart }
        )
        todayMeasurementCount = (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private func attemptStart() {
        if canStartMeasurement {
            Task { await viewModel.start() }
        } else {
            showDailyLimitAlert = true
        }
    }

    /// quartz 가 아니고 (auto/manual) 마지막 24h 안에 안 띄웠으면 토스트 표시.
    private func shouldShowWindingHint() -> Bool {
        let watch = viewModel.watch
        guard watch.movementType != .quartz else { return false }
        let last = UserDefaults.standard.double(forKey: "ticklab.windingHintShownAt")
        let nowEpoch = Date().timeIntervalSince1970
        // 0 = 처음 또는 24h+ 전 → 표시
        return last == 0 || (nowEpoch - last) > 24 * 3600
    }

    private func markWindingHintShown() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "ticklab.windingHintShownAt")
    }

    /// SNR 가 weak 임계값 미만으로 4초 이상 지속됐는지 판정 (read-only).
    /// state mutation 은 `.onChange(of: viewModel.lastSnapshotSNRDB)` 에서 처리 — body-render 중 변경 금지.
    private func isWeakSignalSustained(_ snr: Double) -> Bool {
        // Round 129d: SNR 최소 임계 10dB와 일관. 12 → 10 으로 완화.
        guard snr < 10, let seen = weakSnrSeenAt else { return false }
        return Date().timeIntervalSince(seen) >= 4
    }

    /// Round 15 (Hyemi): body-render 중 DispatchQueue.main.async 로 state 변경하던 antipattern 제거.
    /// onChange callback 으로 옮겨 SwiftUI render 사이클 외부에서 mutation.
    private func updateWeakSnrSeenAt(_ snr: Double?) {
        guard let snr else {
            if weakSnrSeenAt != nil { weakSnrSeenAt = nil }
            return
        }
        if snr < 10 {
            if weakSnrSeenAt == nil { weakSnrSeenAt = Date() }
        } else if weakSnrSeenAt != nil {
            weakSnrSeenAt = nil
        }
    }

    /// Round 170: .failed 상태면 -117.6 같은 garbage live value 가 사용자에게 보이지 않도록
    /// 위쪽 rate / signal / metrics 다 숨기고 failure 카드 + 재측정 버튼만 노출.
    private var isFailed: Bool {
        if case .failed = viewModel.state { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                identityStrip
                if !isFailed {
                    bigRateReadout
                    liveSignalSection
                    metricsSection
                }
                if case .idle = viewModel.state {
                    introHint
                    positionPicker
                    if let movement = viewModel.movement, !movement.shouldDisplayAmplitude {
                        // 사용자 보고 fix: escapement 별 분기 — swissLever medium 시계가 "코액시얼" 안내 받던 버그.
                        let isCoaxial = movement.escapement == .coAxial
                        HelpCard(
                            icon: "info.circle",
                            title: String(localized: isCoaxial
                                          ? "movement.reliability.coaxial.title"
                                          : "movement.reliability.generic.title"),
                            body: String(localized: isCoaxial
                                         ? "movement.reliability.coaxial.notice"
                                         : "movement.reliability.generic.notice")
                        )
                    }
                }
                if case .measuring = viewModel.state {
                    // hysteresis: 4초 sustained weak 일 때만 경고. 깜빡임 방지.
                    if let snr = viewModel.lastSnapshotSNRDB, isWeakSignalSustained(snr) {
                        snrHint(snr)
                    }
                    // Round 170: coupling coaching bars (마이크 접촉 / 락 안정도) 숨김 — 사용자 요청.
                    diagnosticStrip
                }
                controls
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(AppColors.paper0.ignoresSafeArea())
        // Round 139 (Jay High): "측정 시작" 버튼 키를 화면 제목으로 재사용 — "측정" 으로 변경.
        .navigationTitle(String(localized: "measurement.title"))
        .navigationBarTitleDisplayMode(.inline)
        // Round 170 (사용자 보고: "결과보기 버튼 안 넘어감"): item: 핸들러 재복귀.
        // 두 핸들러 동시 등록은 SwiftUI 가 우선순위로 처리 — for: 가 NavigationLink(value:) 매칭에 필요.
        // 결과 화면 진입 흐름: state .completed → completedResultBinding non-nil → item: trigger,
        // OR 사용자가 "결과 보기" 버튼 (NavigationLink value:) 누르면 → for: trigger.
        .navigationDestination(item: completedResultBinding) { result in
            MeasurementResultView(result: result, watch: viewModel.watch, onRetry: {
                viewModel.cancel()
            })
        }
        .navigationDestination(for: MeasurementResult.self) { result in
            MeasurementResultView(result: result, watch: viewModel.watch, onRetry: {
                viewModel.cancel()
            })
        }
        // Round 161 (사용자 보고: "30초 측정인데 35초까지 측정함"):
        // 기존 liveMetrics.elapsedSeconds 는 analyzer cycle(~1s)에 묶여 wall-clock 보다 늦음.
        // state 가 .measuring 으로 바뀌면 wall-clock 30초 후 자동 stop.
        .task(id: stateIsMeasuring) {
            guard stateIsMeasuring else { return }
            try? await Task.sleep(nanoseconds: UInt64(recommendedSeconds * 1_000_000_000))
            if case .measuring = viewModel.state {
                viewModel.stop(modelContext: modelContext)
            }
        }
        // Round 15 (Hyemi): weakSnrSeenAt mutation 을 body 밖으로.
        .onChange(of: viewModel.lastSnapshotSNRDB) { _, newValue in
            updateWeakSnrSeenAt(newValue)
        }
        // Round 18 (Min): background 진입 시 진행 중 measurement 자동 취소.
        //   AVAudioSession interrupt 로 silent-stuck 되는 케이스 차단.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background, stateIsMeasuring {
                viewModel.cancel()
            }
        }
        .onAppear {
            // 사용자 보고: 풀와인딩 안 한 시계에서 -45 s/d → 측정 오류 오해. 1회/24h floating card.
            if shouldShowWindingHint() {
                showWindingHint = true
            }
            refreshTodayMeasurementCount()
        }
        // 측정 완료/취소 시 카운트 갱신 — 다음 measure 시작 전 정확한 한도 검사.
        .onReceive(NotificationCenter.default.publisher(for: .ticklabMeasurementDidEnd)) { _ in
            refreshTodayMeasurementCount()
        }
        // 사용자 보고 fix: 측정 중인 watch 가 외부에서 삭제되면 즉시 측정 cancel.
        //   SwiftData deleted object 에 persist 시도 시 trap 차단.
        .onReceive(NotificationCenter.default.publisher(for: .ticklabWatchWillDelete)) { note in
            if let watchId = note.userInfo?["watchId"] as? UUID,
               watchId == viewModel.watch.id,
               stateIsMeasuring {
                viewModel.cancel()
                dismiss()
            }
        }
        // Free 사용자 하루 측정 한도 초과 alert + Pro 업그레이드 CTA (shell PurchaseRouter).
        .alert(String(localized: "pro.limit.daily_measurement.title"), isPresented: $showDailyLimitAlert) {
            Button(String(localized: "pro.limit.upgrade")) {
                purchaseRouter?.intend(.dailyMeasurement)
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "pro.limit.daily_measurement.body"))
        }
        // Floating modal — 화면 중앙 강조 카드. dim background + tap-to-dismiss.
        // confirmed=true (CTA): 24h timestamp 저장. false (dim tap): 다음 진입에 다시 표시.
        .overlay {
            if showWindingHint {
                WindingHintToast(onDismiss: { confirmed in
                    showWindingHint = false
                    if confirmed {
                        markWindingHintShown()
                    }
                })
                .zIndex(100)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Identity strip

    private var identityStrip: some View {
        HStack(spacing: 12) {
            // Round 158: 사용자 사진 우선 표시, 없으면 silhouette fallback.
            Group {
                if let img = PhotoCache.image(for: viewModel.watch.id, data: viewModel.watch.photoData) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    WatchSilhouette(watch: viewModel.watch, size: 44)
                }
            }
            .frame(width: 44, height: 44)
            .background(AppColors.paper2)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.watch.brand.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(AppColors.ink2)
                Text(viewModel.watch.model)
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .foregroundStyle(AppColors.ink0)
            }
            Spacer()
            // 사용자 보고된 "측정 시간 멈췄다 갑자기 늘어남" 수정:
            // elapsed 를 analyzer cycle (1초) 에 묶지 않고 TimelineView 로 매 프레임 갱신.
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let secs: Double = {
                    guard let start = viewModel.measurementStartedAt else { return 0 }
                    // Round 170: .measuring + .analyzing 둘 다 wall-clock 사용.
                    // 사용자 보고: 측정 완료 후 전 페이지로 가면 상단 timer 가 마지막 elapsed (24s) 로 stuck.
                    //   → .idle/.completed/.failed/.requestingPermission 일 땐 0 으로 초기화.
                    switch viewModel.state {
                    case .measuring, .analyzing:
                        return min(context.date.timeIntervalSince(start), recommendedSeconds)
                    default:
                        return 0
                    }
                }()
                Text(formatElapsed(secs))
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(elapsedColor)
            }
        }
    }

    private var elapsedColor: Color {
        if case .measuring = viewModel.state { return AppColors.accent }
        return AppColors.ink2
    }

    // MARK: - Big rate readout

    private var bigRateReadout: some View {
        let lm = viewModel.liveMetrics
        return VStack(alignment: .leading, spacing: 16) {
            EyebrowLabel(text: String(localized: "measurement.eyebrow.live_rate"))
            // Round 158 (사용자 보고: 실시간 rate swing 으로 사용자 신뢰 낮아짐):
            // 실시간 정확도 숫자 숨김. 측정 중엔 "측정 중..." 만 표시, 최종 결과 화면에서만 rate 표시.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if case .measuring = viewModel.state {
                    Text(String(localized: "measurement.status.measuring"))
                        .font(.system(size: 28, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppColors.ink2)
                } else if case .analyzing = viewModel.state {
                    Text(String(localized: "measurement.status.analyzing"))
                        .font(.system(size: 28, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppColors.accent)
                } else {
                    Text(rateText(displayableLiveRate(lm)))
                        .font(.system(size: 56, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .tracking(-1)
                        .foregroundStyle(rateColorFor(displayableLiveRate(lm)))
                    Text(String(localized: "unit.seconds_per_day"))
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(AppColors.ink2)
                }
            }

            // TimelineView 로 진행률/elapsed 텍스트 갱신.
            // Round (6): progress bar 는 30s 에 걸쳐 변하므로 0.25s 주기로 충분 — 0.1s × 2 timelines 의
            //   30fps 합산 wakeup 부담 절감 (iPhone 11 budget).
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let liveSeconds: Double = {
                    guard let start = viewModel.measurementStartedAt else { return 0 }
                    let raw: Double
                    // Round 170: .measuring + .analyzing 둘 다 wall-clock — stale lm 으로 fallback 차단.
                    switch viewModel.state {
                    case .measuring, .analyzing:
                        raw = context.date.timeIntervalSince(start)
                    default:
                        raw = lm.elapsedSeconds
                    }
                    return min(raw, recommendedSeconds)
                }()
                let progress = min(1.0, liveSeconds / recommendedSeconds)
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1.5).fill(AppColors.rule).frame(height: 3)
                            RoundedRectangle(cornerRadius: 1.5).fill(AppColors.accent)
                                .frame(width: max(0, CGFloat(progress)) * geo.size.width, height: 3)
                        }
                    }
                    .frame(height: 3)
                    HStack {
                        // Round (사용자 요청): elapsed/total 표시 ("5s / 30s") 제거 — 카운트다운 한 줄로 충분.
                        if case .measuring = viewModel.state {
                            let remaining = Int(max(0, recommendedSeconds - liveSeconds).rounded(.up))
                            Text(String(format: String(localized: "measurement.countdown"), remaining))
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppColors.accent)
                                .accessibilityLabel(String(format: String(localized: "measurement.countdown.a11y"), remaining))
                        }
                        Spacer()
                    if case .measuring = viewModel.state {
                        HStack(spacing: 5) {
                            Circle().fill(AppColors.danger).frame(width: 7, height: 7)
                                .opacity(0.9)
                            Text(String(localized: "measurement.rec_label")).font(.system(size: 10.5, design: .monospaced))
                                .tracking(1.2).foregroundStyle(AppColors.ink2)
                            if let snr = lm.snrDB {
                                Text(String(format: String(localized: "measurement.snr_label"), Int(snr.rounded())))
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(AppColors.ink3)
                            }
                        }
                    }
                }
            }
        }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.paper0)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func rateText(_ rate: Double?) -> String {
        guard let rate else { return "—" }
        if case .idle = viewModel.state { return "—" }
        return (rate >= 0 ? "+" : "") + String(format: "%.1f", rate)
    }
    private func displayableLiveRate(_ lm: LiveMetrics) -> Double? {
        guard let rate = lm.rateSecondsPerDay else { return nil }
        // 신뢰도 25 미만 lock 은 거의 noise. 가짜 rate 숨김.
        if lm.confidenceScore < 25 { return nil }
        return rate
    }
    private func rateColorFor(_ rate: Double?) -> Color {
        guard let rate else { return AppColors.ink3 }
        if case .idle = viewModel.state { return AppColors.ink3 }
        let abs = abs(rate)
        if abs <= 6 { return AppColors.success }
        if abs <= 20 { return AppColors.warning }
        return AppColors.danger
    }

    // MARK: - Live signal

    /// Round 52/114: 디자인 SSOT components.jsx LiveWaveform 와 통일.
    /// 사용자 보고 "처음 설정 그래프 스타일과 같이" — samples nil 전달해 항상 합성 sin + tic/toc dots 표시.
    /// 실 측정의 raw wave samples 는 진단 / debugging 용으로 다른 위치에 표시 가능.
    private var liveSignalSection: some View {
        // Round 111 (박현우): 측정 중에는 실 waveform 전달 — 합성 sin은 idle 상태에서만.
        let isRunning: Bool
        if case .measuring = viewModel.state { isRunning = true } else { isRunning = false }
        return VStack(alignment: .leading, spacing: 10) {
            EyebrowLabel(text: String(localized: "measurement.eyebrow.live_signal"), number: "02")
            LiveWaveformCanvas(
                running: isRunning,
                samples: isRunning ? viewModel.waveformSamples : nil,
                // Round 158: confidence > 30 (실제 lock) 일 때만 dots 표시.
                // lockMem 의 stale bph (confidence decayed to 0) 는 fake lock 으로 보임 → 차단.
                lockedBPH: (isRunning && viewModel.liveMetrics.confidenceScore > 30) ? viewModel.liveMetrics.bph : nil,
                // 사용자 요청 (실시간 tic/toc): DSP 검출 onset timestamps + measurement start wall-clock.
                //   60fps 흐름으로 점이 부드럽게 viewport 흐름 (elapsed analyzer cycle 1초 stuck 회피).
                recentOnsetTimes: isRunning ? viewModel.liveMetrics.recentOnsetTimes : nil,
                measurementStartedAt: isRunning ? viewModel.measurementStartedAt : nil,
                showProInfo: viewModel.preferences.userMode == .pro
            )
            .frame(height: 170)
        }
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        let lm = viewModel.liveMetrics
        return VStack(alignment: .leading, spacing: 10) {
            EyebrowLabel(text: String(localized: "measurement.eyebrow.metrics"), number: "03")
            // Round 170: 측정 중 amplitude + 신뢰도 둘 다 제거.
            // 사용자 보고: "낮게 나오면 어차피 신뢰가 없다고 생각할거" — 측정 진행 중 신뢰도 swing 이
            // 오히려 사용자 불안감 키움. 최종 결과 화면에서만 신뢰도 표시.
            MetricGrid(cells: [
                MetricBadge(
                    label: String(localized: "measurement.metric.beat_error"),
                    value: lm.beatErrorMs.map { String(format: "%.2f", $0) } ?? "—",
                    unit: "ms",
                    tone: lm.beatErrorMs.map { $0 < 0.5 ? .success : .warning } ?? .neutral
                ),
                MetricBadge(
                    label: String(localized: "measurement.metric.bph"),
                    value: lm.bph.map { "\($0)" } ?? "\(viewModel.movement?.bph ?? 28_800)"
                )
            ])
        }
    }

    // MARK: - Hints

    private var introHint: some View {
        // Round 170 (UX 개선): 단일 카드 → 3-step 가이드 + 정확도 팁.
        // 사용자 측정 데이터: immobile watch σ ±1.75 vs handling σ ±8.9 → 자세 안정이 핵심.
        VStack(spacing: 10) {
            HelpCard(
                icon: "iphone",
                title: String(localized: "measurement.setup.step1.title"),
                body: String(localized: "measurement.setup.step1.body")
            )
            HelpCard(
                icon: "mic.circle",
                title: String(localized: "measurement.setup.step2.title"),
                body: String(localized: "measurement.setup.step2.body")
            )
            HelpCard(
                icon: "speaker.slash",
                title: String(localized: "measurement.setup.step3.title"),
                body: String(localized: "measurement.setup.step3.body")
            )
            // 사용자 보고 fix: 이전엔 "3-5회 평균" 권장 vs Free 일일 3회 한도 충돌 — Free 는 3회 기준,
            //   Pro 는 무제한 표현으로 분기.
            HelpCard(
                icon: "chart.bar.fill",
                title: String(localized: "measurement.tips.average.title"),
                body: preferences.isPro
                    ? String(localized: "measurement.tips.average.body.pro")
                    : String(localized: "measurement.tips.average.body.free"),
                tone: .info
            )
            // Round 170 (사용자 요청): 측정값은 참고용 명시 — 법적/사용자 기대 관리.
            HelpCard(
                icon: "exclamationmark.triangle",
                title: String(localized: "measurement.disclaimer.title"),
                body: String(localized: "measurement.disclaimer.body"),
                tone: .warning
            )
        }
    }

    /// 페르소나 (김재철) Priority 1 wish: position picker — 측정 전 자세 선택.
    /// 6 자세 chip 가로 스크롤. 선택 안 하면 unknown 으로 저장.
    /// Round 22 (Doyoon): filter 매 body 마다 reallocate 하지 않도록 static 으로 hoist.
    private static let visiblePositions: [Position] = Position.allCases.filter { $0 != .unknown }

    private var positionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowLabel(text: String(localized: "measurement.position.title"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.visiblePositions, id: \.self) { pos in
                        Button {
                            viewModel.selectedPosition = (viewModel.selectedPosition == pos) ? .unknown : pos
                        } label: {
                            Text(pos.localizedName)
                                .font(.system(size: 12.5, weight: .medium))
                                .padding(.horizontal, 12)
                                // Round 117 (A11y): WCAG 44pt 최소 터치 영역.
                                .frame(height: 44)
                                .foregroundStyle(viewModel.selectedPosition == pos ? AppColors.paper0 : AppColors.ink1)
                                .background(viewModel.selectedPosition == pos ? AppColors.ink0 : AppColors.paper1)
                                .overlay(Capsule().stroke(AppColors.rule, lineWidth: 1))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    // Round 22 (Doyoon): coachingBars/coachingRow/coachingColor 삭제 — Round 170 에서
    //   사용자 요청으로 화면에서 제거됐는데 implementation 만 남아 있던 dead code (50+ lines).

    /// 1행: Mic (raw RMS) → 2행: SNR (envelope) → 3행: Onsets → 4행: BPH 락
    /// 사용자가 어디서 막히는지 즉시 보임.
    private var diagnosticStrip: some View {
        let lm = viewModel.liveMetrics
        return VStack(spacing: 6) {
            HStack(spacing: 10) {
                diagnosticCell(
                    label: String(localized: "measurement.diagnostic.mic"),
                    value: lm.rawRMSDB.map { String(format: "%.0f dB", $0) } ?? "—",
                    tone: micTone(lm.rawRMSDB)
                )
                Divider().frame(height: 24).background(AppColors.rule)
                diagnosticCell(
                    label: String(localized: "measurement.diagnostic.snr"),
                    value: lm.snrDB.map { String(format: "%.0f", $0) } ?? "—",
                    tone: snrTone(lm.snrDB)
                )
                Divider().frame(height: 24).background(AppColors.rule)
                diagnosticCell(
                    label: String(localized: "measurement.diagnostic.onsets"),
                    value: lm.onsetCount.map { "\($0)" } ?? "—",
                    tone: onsetTone(lm.onsetCount)
                )
                Divider().frame(height: 24).background(AppColors.rule)
                diagnosticCell(
                    label: String(localized: "measurement.diagnostic.bph"),
                    // Round 158: nominalBph echo (lock 잡힐 때까지 nominal 표시).
                    value: lm.bph.map { "\($0)" } ?? "\(viewModel.movement?.bph ?? 28_800)",
                    tone: lm.bph != nil ? .success : .neutral
                )
            }
            // 진단 메시지
            if let hint = diagnosticHint(lm) {
                Text(hint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppColors.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func micTone(_ db: Double?) -> MetricBadge.Tone {
        guard let db else { return .neutral }
        // -120: dead, -60: 잘 잡힘, -40: 시끄러움
        if db < -80 { return .danger }
        if db < -60 { return .warning }
        return .success
    }
    private func snrTone(_ snr: Double?) -> MetricBadge.Tone {
        guard let snr else { return .neutral }
        if snr < 12 { return .warning }
        if snr < 20 { return .neutral }
        return .success
    }
    private func onsetTone(_ count: Int?) -> MetricBadge.Tone {
        guard let count else { return .neutral }
        // 6초 윈도우 28800 BPH 면 ~48 onsets, 21600 BPH 면 ~36
        if count < 5 { return .warning }
        if count > 100 { return .danger } // 너무 많으면 노이즈 detect
        return .success
    }

    /// 진단 hint — 사용자 액션 가이드. Round 175: 사용자 친화 카피 (기술 jargon 최소화).
    private func diagnosticHint(_ lm: LiveMetrics) -> String? {
        // Round 129 Critical: AirPods/BT 마이크 라우팅 감지 — 시계 소리 못 들음.
        let activeMic = AudioInputManager.shared.activeMicrophoneType
        if activeMic == .bluetooth {
            return NSLocalizedString("measurement.hint.bluetooth", comment: "")
        }
        if activeMic == .wired {
            return NSLocalizedString("measurement.hint.wired", comment: "")
        }
        // Round 129 BUG FIX: 절대값(120) → 비율(초당 onset 수) 기반으로 수정.
        // 28800 BPH = 16 onsets/s. 30/s 이상이면 진짜 주변 소음.
        if let onsets = lm.onsetCount, lm.elapsedSeconds > 4 {
            let rate = Double(onsets) / lm.elapsedSeconds
            if rate > 30 {
                return NSLocalizedString("measurement.hint.noise", comment: "")
            }
            // BPH lock 실패하지만 onset은 있는 경우 — 케이스백 더 밀착 안내.
            if rate > 5, rate <= 30 {
                return NSLocalizedString("measurement.hint.press_closer", comment: "")
            }
        }
        // 마이크가 거의 무신호.
        if let db = lm.rawRMSDB, db < -80 {
            return NSLocalizedString("measurement.hint.no_signal", comment: "")
        }
        // Tic 거의 감지 안 됨.
        if let onsets = lm.onsetCount, onsets < 5, lm.elapsedSeconds > 4 {
            return NSLocalizedString("measurement.hint.weak_detection", comment: "")
        }
        // BPH lock 시도 중.
        if lm.bph == nil, let onsets = lm.onsetCount, onsets > 5 {
            return NSLocalizedString("measurement.hint.analyzing", comment: "")
        }
        // BPH lock 실패.
        if lm.lockFailReason != nil, lm.bph == nil, lm.elapsedSeconds > 8 {
            #if DEBUG
            return String(format: NSLocalizedString("measurement.hint.no_lock_debug", comment: ""), lm.lockFailReason ?? "")
            #else
            return NSLocalizedString("measurement.hint.no_lock", comment: "")
            #endif
        }
        return nil
    }

    private func diagnosticCell(label: String, value: String, tone: MetricBadge.Tone = .neutral) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(AppColors.ink2)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(diagnosticToneColor(tone))
        }
        .frame(maxWidth: .infinity)
    }

    private func diagnosticToneColor(_ tone: MetricBadge.Tone) -> Color {
        switch tone {
        case .neutral: return AppColors.ink1
        case .success: return AppColors.success
        case .warning: return AppColors.warning
        case .danger:  return AppColors.danger
        }
    }

    /// SNR 약 신호 안내 — 측정 중 hint 카드.
    /// 사용자 보고된 "감지 못했다고 나옴" 혼동 수정: title 을 "신호가 약함" 으로 명확히.
    /// (실패가 아닌 "측정 중 신호 약함" 안내라는 점을 사용자가 즉시 파악)
    private func snrHint(_ snr: Double) -> some View {
        HelpCard(
            icon: "waveform.path.ecg",
            title: String(localized: "measurement.hint.weak.title"),
            body: String(localized: snr < 12 ? "measurement.hint.move_closer" : "measurement.hint.acceptable"),
            tone: snr < 12 ? .warning : .info
        )
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        switch viewModel.state {
        case .idle:
            PrimaryButton(String(localized: "measurement.button.start"), icon: "mic") {
                attemptStart()
            }
            .padding(.top, 4)
        case .requestingPermission:
            ProgressView(String(localized: "measurement.status.permission_pending"))
                .padding(.top, 8)
        case .measuring:
            VStack(spacing: 8) {
                PrimaryButton(String(localized: "measurement.button.stop"),
                              style: .bordered, icon: "stop.fill") {
                    viewModel.stop(modelContext: modelContext)
                }
                if viewModel.liveMetrics.elapsedSeconds < 5 {
                    Text(String(localized: "measurement.hint.minimum_duration"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppColors.ink3)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 4)
        case .analyzing:
            // Round 170: stop() 직후 background 분석 진행 중 — UI 즉시 반응.
            VStack(spacing: 10) {
                ProgressView()
                Text(String(localized: "measurement.status.analyzing"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.ink2)
            }
            .padding(.top, 8)
        case .completed(let result):
            // Round 131 (실기기 stuck 보고): ProgressView → 명시적 Button.
            // navigationDestination(item:) iOS auto trigger 실패 시 사용자가 직접 결과 화면 진입.
            NavigationLink(value: result) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                    Text(String(localized: "measurement.button.see_result"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 8)
        case .failed(let reason):
            failureCard(reason: reason)
        }
    }

    @ViewBuilder
    private func failureCard(reason: MeasurementViewModel.FailureReason) -> some View {
        VStack(spacing: 12) {
            HelpCard(
                icon: failureIcon(reason),
                // Round 57: String.LocalizationValue + runtime string → defaultValue 버그. NSLocalizedString.
                title: NSLocalizedString(failureTitleKey(reason), comment: ""),
                body: NSLocalizedString(failureBodyKey(reason), comment: ""),
                tone: .warning
            )
            // Round 57: permissionDenied 분기 시 "설정 열기" 를 prominent primary, 그 외엔 retry+cancel pair.
            if reason == .permissionDenied {
                PrimaryButton(String(localized: "measurement.permission.openSettings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                PrimaryButton(String(localized: "common.cancel"), style: .bordered) {
                    dismiss()
                }
            } else {
                HStack(spacing: 8) {
                    PrimaryButton(String(localized: "measurement.button.retry"), style: .bordered) {
                        attemptStart()
                    }
                    PrimaryButton(String(localized: "common.cancel"), style: .bordered) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func failureIcon(_ r: MeasurementViewModel.FailureReason) -> String {
        switch r {
        case .permissionDenied:     return "mic.slash"
        case .tooShort:             return "timer"
        case .noSignal:             return "waveform.slash"
        case .audioEngineFailure:   return "exclamationmark.triangle"
        case .unsupportedMovement:  return "questionmark.circle"
        case .lockFailure:          return "exclamationmark.shield"
        }
    }
    private func failureTitleKey(_ r: MeasurementViewModel.FailureReason) -> String {
        switch r {
        case .permissionDenied:     return "measurement.permission.title"
        case .tooShort:             return "measurement.fail.too_short.title"
        case .noSignal:             return "measurement.fail.no_signal.title"
        case .audioEngineFailure:   return "measurement.fail.engine.title"
        case .unsupportedMovement:  return "measurement.fail.unsupported.title"
        case .lockFailure:          return "measurement.fail.lock.title"
        }
    }
    private func failureBodyKey(_ r: MeasurementViewModel.FailureReason) -> String {
        switch r {
        case .permissionDenied:     return "measurement.permission.body"
        case .tooShort:             return "measurement.fail.too_short.body"
        case .noSignal:             return "measurement.fail.no_signal.body"
        case .audioEngineFailure:   return "measurement.fail.engine.body"
        case .unsupportedMovement:  return "measurement.fail.unsupported.body"
        case .lockFailure:          return "measurement.fail.lock.body"
        }
    }

    // MARK: - Navigation binding

    private var completedResultBinding: Binding<MeasurementResult?> {
        Binding(
            get: {
                if case .completed(let result) = viewModel.state { return result }
                return nil
            },
            set: { newValue in
                if newValue == nil { viewModel.cancel() }
            }
        )
    }

    private func formatElapsed(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

#Preview {
    NavigationStack {
        MeasurementView(
            watch: Watch(brand: "Tudor", model: "Black Bay 58", caliber: "Tudor_MT5602"),
            preferences: UserPreferences()
        )
    }
    .modelContainer(for: [Watch.self, WatchMeasurement.self], inMemory: true)
}
