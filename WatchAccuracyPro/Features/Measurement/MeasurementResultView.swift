import SwiftUI

struct MeasurementResultView: View {
    let result: MeasurementResult
    let watch: Watch
    /// Round 133: 부모(MeasurementView) 가 state 를 .idle 로 reset 후 dismiss 하도록 콜백 주입.
    /// 없으면 단순 dismiss (sheet/standalone 으로 쓰는 경우).
    var onRetry: (() -> Void)? = nil
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var gradeTileSize: CGFloat = 64
    @ScaledMetric(relativeTo: .largeTitle) private var gradeTileFont: CGFloat = 44
    /// 사용자 보고 fix: verdict headline/body Dynamic Type 대응 — 노안 사용자가 XL 글자 크기 사용 시도.
    @ScaledMetric(relativeTo: .title) private var scaledHeadlineSize: CGFloat = 28
    @ScaledMetric(relativeTo: .title) private var scaledHeadlineSizeLow: CGFloat = 32
    @ScaledMetric(relativeTo: .body) private var scaledBodySize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var scaledBodySizeLow: CGFloat = 15
    /// Round 23 (Doyoon): onAppear haptic 가 매 reentry (share sheet dismiss 등) 마다 fire 하던 버그.
    @State private var didFireHaptic = false

    private var movement: Movement? {
        watch.caliber.flatMap { MovementDatabase.shared.movement(id: $0) }
    }

    /// verdict.headline 끝 글자가 종결 부호/한국어 종결어미면 마침표 추가 안 함.
    private func needsTrailingDot(_ s: String) -> Bool {
        guard let last = s.last else { return false }
        // 이미 마침표/물음표/느낌표 있으면 skip.
        if [".", "?", "!", "。", "?", "!"].contains(String(last)) { return false }
        // 한국어 종결어미 "다", "요" 끝나면 마침표 자연.
        // 이모지/특수 문자로 끝나면 마침표 어색 → skip.
        if last.isLetter || last.isNumber { return true }
        return false
    }

    /// 신호 품질(신뢰도·박동오차)은 양호한데 rate 가 비정상적으로 크면
    /// 측정 오류(알고리즘 잘못된 주기 lock)일 가능성이 높음 → 재측정 권장.
    /// 사용자 보고 fix: 이전 조건은 모든 abs(rate)>30 결과를 "의심" 표시 (lockFailure 가 이미 beat<1.5 거름).
    ///   진폭 변동성 또는 cross-window delta 도 함께 봐서 정상 큰 rate 와 알고리즘 lock 오류 구분.
    private var isSuspiciousMeasurement: Bool {
        // rate 가 매우 큼 (>45) 이면서 신뢰도도 매우 높으면 — drift 정상 시계는 ±60s/d 도 가능하므로 신호 품질 임계 ↑.
        abs(result.rateSecondsPerDay) > 45
        && result.confidenceScore >= 70
        && result.beatErrorMs < 1.0
    }

    /// Round 170: OLS slope uncertainty 기반 rate 정밀도 (±X s/d). nil 이면 표시 X.
    private var rateUncertaintyString: String? {
        guard let rms = result.residualRMSSeconds, result.beatCount > 1 else { return nil }
        let n = Double(result.beatCount)
        let period = 3600.0 / Double(result.bph)
        let uncertainty = rms * 12.0.squareRoot() / pow(n, 1.5) / period * 86400.0
        guard uncertainty.isFinite, uncertainty < 100 else { return nil }
        return String(format: "±%.1f s/d", uncertainty)
    }

    private var verdict: (toneColor: Color, tone: Chip.Tone, headline: String, body: String) {
        let abs = abs(result.rateSecondsPerDay)
        // 페르소나 (정수민) 피드백: 1회 측정으로 "서비스 권장" 은 감정적 과장.
        // 측정 회수 < 3 이면 service verdict 대신 caution + "한 번 더 측정 권장".
        // Round 169: SwiftData reactive 로 인해 watch.measurements 가 이미 현재 측정 포함된 경우 double-count 방지.
        let measurementCount = max(1, watch.measurements.count)
        // Round 142 (Hyemi 4 H1 BUG): success cutoff 다른 화면 (CollectionView/WatchDetailView 등) <=6 인데
        // 여기만 <=10 이었음 — 같은 측정이 list 에선 warning, hero verdict 에선 success 모순. 6 으로 통일.
        if abs <= 6 {
            return (AppColors.success, .success,
                    String(localized: "result.verdict.ok.title"),
                    String(localized: "result.verdict.ok.body"))
        } else if abs <= 20 {
            return (AppColors.warning, .warning,
                    String(localized: "result.verdict.caution.title"),
                    String(localized: "result.verdict.caution.body"))
        } else if measurementCount < 3 {
            // 측정 누적 부족 — service 대신 "재측정 권장".
            return (AppColors.warning, .warning,
                    String(localized: "result.verdict.first_anomaly.title"),
                    String(localized: "result.verdict.first_anomaly.body"))
        } else {
            return (AppColors.danger, .danger,
                    String(localized: "result.verdict.service.title"),
                    String(localized: "result.verdict.service.body"))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Round 129 (실기기 피드백): 저장 완료 확인 배너 — AI 스피너와 혼동 방지.
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.success)
                        .font(.system(size: 14))
                    Text(String(localized: "result.saved.hint"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.success)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(AppColors.success.opacity(0.1))
                .clipShape(Capsule())
                .frame(maxWidth: .infinity, alignment: .center)
                if isSuspiciousMeasurement { suspiciousRemeasureBanner }
                // Round 153 (Müller): A/B/C/F 신뢰도 큰 뱃지 + 클레임 텍스트.
                if let grade = result.reliabilityGrade {
                    reliabilityGradeBadge(grade)
                }
                editorialVerdict
                rateDialCard
                // Round 45 — 디자인 SSOT COSC bar 추가 (rateDial 후).
                COSCBar(rate: result.rateSecondsPerDay)
                    .padding(.horizontal, 4)
                metricsSection
                if preferences.userMode == .pro { detailsSection }
                // Round 160: 진단 카드 — Apple Intelligence 가능하면 실제 LLM, 아니면 rule-based.
                AIDiagnosisCard(
                    rateSecondsPerDay: result.rateSecondsPerDay,
                    confidence: result.confidenceScore,
                    watch: watch,
                    movement: movement,
                    result: result
                )
                if let note = result.reliabilityNote { reliabilityHelp(note) }
                // 페르소나 (박지영, 입문자) wish: "그래서 다음엔 뭘?" 가이드.
                // 사용자 보고 fix: userMode 기본 .pro 로 바뀌어 novice 가드가 dead → 첫 측정 기준으로.
                if watch.measurements.count <= 1 {
                    nextStepGuide
                }
                actions
                // Round 170: 참고용 disclaimer — 결과 화면 하단.
                Text(String(localized: "measurement.disclaimer.body"))
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.ink3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(AppColors.paper0.ignoresSafeArea())
        .navigationTitle(String(localized: "result.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Round 23 (Doyoon): 최초 1회만 haptic. share sheet 닫고 reentry 시 재발화 차단.
            guard !didFireHaptic else { return }
            didFireHaptic = true
            let gen = UINotificationFeedbackGenerator()
            switch result.reliabilityGrade {
            case .a, .b:    gen.notificationOccurred(.success)
            case .c:        gen.notificationOccurred(.warning)
            case .f, .none: UISelectionFeedbackGenerator().selectionChanged()
            }
        }
    }

    // MARK: - Editorial verdict

    // Round 153 (Müller): 신뢰도 등급 뱃지.
    // Round 170 (사용자 보고: hardcoded "±10 s/d" 와 실제 OLS ±0.1 s/d 모순):
    // residualRMS 기반 실측 uncertainty 있으면 그 값 사용. 없으면 grade hardcoded fallback.
    private func reliabilityGradeBadge(_ grade: ReliabilityGrade) -> some View {
        let actualClaim: String? = {
            guard let uncStr = rateUncertaintyString else { return nil }
            let suffix: String = {
                switch grade {
                case .a: return String(localized: "result.grade.a.suffix")
                case .b: return String(localized: "result.grade.b.suffix")
                case .c: return String(localized: "result.grade.c.suffix")
                case .f: return String(localized: "result.grade.f.suffix")
                }
            }()
            return "\(uncStr) \(suffix)"
        }()
        let (color, claim): (Color, String) = {
            switch grade {
            case .a: return (AppColors.success, actualClaim ?? String(localized: "result.grade.a.claim"))
            case .b: return (AppColors.ink0,    actualClaim ?? String(localized: "result.grade.b.claim"))
            case .c: return (AppColors.warning, actualClaim ?? String(localized: "result.grade.c.claim"))
            case .f: return (AppColors.danger,  actualClaim ?? String(localized: "result.grade.f.claim"))
            }
        }()
        return HStack(spacing: 14) {
            Text(grade.rawValue.uppercased())
                .font(.system(size: gradeTileFont, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: gradeTileSize, height: gradeTileSize)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "result.grade.eyebrow").uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(AppColors.ink2)
                Text(claim)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.ink0)
                // 일반인 친화 한 줄 설명 (박지영 페르소나)
                Text({
                    switch grade {
                    case .a: return String(localized: "result.grade.a.gloss")
                    case .b: return String(localized: "result.grade.b.gloss")
                    case .c: return String(localized: "result.grade.c.gloss")
                    case .f: return String(localized: "result.grade.f.gloss")
                    }
                }())
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var editorialVerdict: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: NSLocalizedString("result.eyebrow.subtitle", comment: ""),
                        watch.brand,
                        DateFormatter.shortDateTime.string(from: Date()))
                    .uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.2)
                .foregroundStyle(AppColors.ink3)
            // Round 170 (팀 토론): low-confidence (C/F) 일 때 headline 더 크게 + body 강조.
            // 신뢰 안 되는 숫자보다 메시지가 우선 — 사용자에게 "재측정 권장" 명확히.
            // 사용자 보고 fix: .system(size:) 는 Dynamic Type scaling 안 됨 → @ScaledMetric 으로 노안 사용자 대응.
            // 사용자 보고 fix: 일부 verdict.headline 이 이미 종결어미/마침표/이모지 포함 → 중복 마침표 방지.
            //   trailing 마침표/물음표/느낌표가 이미 있으면 추가 X.
            Text("\u{201C}\(verdict.headline)\(needsTrailingDot(verdict.headline) ? "." : "")\u{201D}")
                .font(.system(size: isHighConfidenceGrade ? scaledHeadlineSize : scaledHeadlineSizeLow,
                              weight: .semibold, design: .serif))
                .foregroundStyle(verdict.toneColor)
                .lineSpacing(2)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            Text(verdict.body)
                .font(.system(size: isHighConfidenceGrade ? scaledBodySize : scaledBodySizeLow,
                              weight: isHighConfidenceGrade ? .regular : .medium))
                .foregroundStyle(AppColors.ink0)
                .lineSpacing(3)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: - Rate dial card

    /// Round 170 (팀 토론 확장): "결과를 크게 보여줄 가치가 있는가" 판단.
    /// 1) Grade C/F (정밀도 부족) → 숫자 못 믿음
    /// 2) COSC 밖 (-4 ~ +6 외) → detection 시스템 bias 의심 영역, 사용자 정상 시계도 큰 음수 나옴
    /// 둘 중 하나라도 해당하면 메시지 우선 모드.
    private var isHighConfidenceGrade: Bool {
        let inCOSC = result.rateSecondsPerDay >= -4 && result.rateSecondsPerDay <= 6
        let goodGrade: Bool = {
            guard let g = result.reliabilityGrade else { return true }
            return g == .a || g == .b
        }()
        return inCOSC && goodGrade
    }

    private var rateDialCard: some View {
        let bigFont: CGFloat = isHighConfidenceGrade ? 60 : 28
        let bigColor: Color = isHighConfidenceGrade ? verdict.toneColor : AppColors.ink3
        let dialSize: CGFloat = isHighConfidenceGrade ? 220 : 160
        let dialOpacity: Double = isHighConfidenceGrade ? 1.0 : 0.55
        return VStack(spacing: 6) {
            Text(String(localized: "watch.label.rate").uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.2)
                .foregroundStyle(AppColors.ink2)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formatRate(result.rateSecondsPerDay))
                    .font(.system(size: bigFont, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .tracking(-1.5)
                    .foregroundStyle(bigColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text(String(localized: "unit.seconds_per_day"))
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundStyle(AppColors.ink2)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(format: NSLocalizedString("a11y.rate_value", comment: ""), formatRate(result.rateSecondsPerDay), String(localized: "unit.seconds_per_day")))
            // 낮은 신뢰도 등급일 때 "참고용 수치" 캡션
            if !isHighConfidenceGrade {
                Text(String(localized: "result.rate.reference_only").uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(AppColors.ink3)
            }
            if let rateUncertainty = rateUncertaintyString {
                // Round (기능 B): master plan 의 ±s/d 정밀도 표시 — Chip 으로 인지도 강화.
                Chip(rateUncertainty, tone: .neutral, small: true)
                    .accessibilityLabel(String(format: String(localized: "a11y.rate_uncertainty"), rateUncertainty))
            }
            RateDial(rate: result.rateSecondsPerDay, size: dialSize)
                .opacity(dialOpacity)
                .padding(.top, 4)
                .transition(.scale.combined(with: .opacity))
            HStack(spacing: 8) {
                let inCosc = result.rateSecondsPerDay >= -4 && result.rateSecondsPerDay <= 6
                Chip(
                    inCosc ? String(localized: "result.cosc.in") : String(localized: "result.cosc.out"),
                    tone: inCosc ? .success : .neutral,
                    small: true
                )
                Chip(String(localized: "result.cosc.range"), small: true)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(AppColors.paper0)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        // Round 170 (사용자 보고: "amp 셀 자체 제거"):
        // 마이크 기반 amplitude 측정은 케이스 디자인·자세 민감도로 신뢰성 낮음 — 모든 무브먼트에서 제거.
        // 3 cell grid (beat error / BPH / 신뢰도).
        let cells: [MetricBadge] = [
            MetricBadge(
                label: String(localized: "watch.label.beat_error"),
                value: String(format: "%.2f", result.beatErrorMs),
                unit: "ms",
                hint: result.beatErrorMs < 0.5
                    ? String(localized: "result.beat.excellent")
                    : String(localized: "result.beat.acceptable"),
                tone: result.beatErrorMs < 0.5 ? .success : .warning,
                big: true
            ),
            MetricBadge(
                label: String(localized: "watch.spec.bph"),
                value: "\(result.bph)",
                hint: movement?.escapement.rawValue.uppercased() ?? NSLocalizedString("result.escapement.fallback", comment: ""),
                big: true
            ),
            MetricBadge(
                label: String(localized: "confidence.label"),
                value: "\(result.confidenceScore)",
                hint: String(format: NSLocalizedString("result.snr_beats_hint", comment: ""),
                             result.snrDB, result.beatCount),
                tone: result.confidenceScore >= 80 ? .success : .warning,
                big: true
            )
        ]
        return VStack(alignment: .leading, spacing: 10) {
            EyebrowLabel(text: String(localized: "result.section.metrics"), number: "01")
            MetricGrid(cells: cells)
        }
    }

    // Round 23 (Doyoon): amplitudeHint() 삭제 — Round 170 amplitude metric cell 제거 후 caller 없음.
    //   Localizable.strings 의 result.amplitude.{coaxial,healthy,borderline,service} 도 dead.

    // MARK: - Details (expert mode)

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            EyebrowLabel(text: String(localized: "result.section.details"), number: "02")
            VStack(spacing: 0) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    SpecRow(label: String(localized: "result.label.duration"),
                            value: String(format: NSLocalizedString("unit.seconds_short", comment: ""), result.durationSeconds))
                    SpecRow(label: String(localized: "result.label.beat_count"),
                            value: "\(result.beatCount)")
                    SpecRow(label: String(localized: "result.label.snr"),
                            value: String(format: "%.1f dB", result.snrDB))
                    // 페르소나 (김재철, 워치메이커) 피드백: position 이 항상 "—" 라 무의미.
                    // 대신 escapement 타입 노출 (movement DB 에서 가져옴).
                    SpecRow(label: String(localized: "watch.spec.escapement"),
                            value: movement?.escapement.rawValue ?? "—")
                }
            }
            .padding(14)
            .background(AppColors.paper0)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    /// 입문자 첫 측정 후 다음 단계 가이드. "1주일 뒤 다시 측정" 등.
    private var nextStepGuide: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "result.next_step.eyebrow").uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(2)
                .foregroundStyle(AppColors.ink2)
            Text(String(localized: "result.next_step.body"))
                .font(.system(size: 13.5))
                .foregroundStyle(AppColors.ink1)
                .lineSpacing(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.accentTint)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.accent.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Reliability help

    private func reliabilityHelp(_ note: ReliabilityNote) -> some View {
        HelpCard(
            icon: "info.circle",
            title: String(localized: String.LocalizationValue(note.titleKey)),
            body: String(localized: String.LocalizationValue(note.bodyKey))
        )
    }

    // MARK: - Suspicious Measurement Banner

    private var suspiciousRemeasureBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColors.warning)
                    .font(.system(size: 16))
                Text(String(localized: "result.suspicious.title"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.ink0)
            }
            Text(String(localized: "result.suspicious.body"))
                .font(.system(size: 13))
                .foregroundStyle(AppColors.ink2)
                .fixedSize(horizontal: false, vertical: true)
            // 사용자 보고 fix: warning banner 의 retry CTA 가 약한 tertiary link 처럼 보였음 → 강한 filled 버튼으로 prominence ↑.
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if let onRetry { onRetry() } else { dismiss() }
            } label: {
                Label(String(localized: "result.suspicious.retry"), systemImage: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AppColors.warning)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.warning.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.warning.opacity(0.4), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    // Round 125 (이도현 High): 측정 결과 즉시 공유 버튼 추가.
    @State private var showShareCard = false

    private var actions: some View {
        VStack(spacing: 10) {
            if isHighConfidenceGrade {
                PrimaryButton(String(localized: "result.action.done"), style: .accent, icon: "checkmark") {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if let onRetry { onRetry() } else { dismiss() }
                }
                HStack(spacing: 10) {
                    PrimaryButton(String(localized: "result.action.again"), style: .bordered, icon: "arrow.clockwise") {
                        if let onRetry { onRetry() } else { dismiss() }
                    }
                    PrimaryButton(String(localized: "result.action.share"), style: .bordered, icon: "square.and.arrow.up") {
                        showShareCard = true
                    }
                }
            } else {
                // Round 10: 낮은 신뢰도 — 재측정을 primary로.
                PrimaryButton(String(localized: "result.action.again"), style: .accent, icon: "arrow.clockwise") {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if let onRetry { onRetry() } else { dismiss() }
                }
                HStack(spacing: 10) {
                    PrimaryButton(String(localized: "result.action.done"), style: .bordered, icon: "checkmark") {
                        if let onRetry { onRetry() } else { dismiss() }
                    }
                    PrimaryButton(String(localized: "result.action.share"), style: .bordered, icon: "square.and.arrow.up") {
                        showShareCard = true
                    }
                }
            }
        }
        .padding(.top, 4)
        // Round 170: 측정 결과 화면에서 공유 → watch + 최신 measurement 직접 전달.
        .sheet(isPresented: $showShareCard) {
            ShareCardComposerView(
                entry: nil,
                watch: watch,
                measurement: watch.measurements.max(by: { $0.timestamp < $1.timestamp }),
                directRate: result.rateSecondsPerDay
            )
        }
    }
}

// MARK: - SpecRow helper

struct SpecRow: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(AppColors.ink2)
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(AppColors.ink0)
        }
    }
}

extension DateFormatter {
    static let shortDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

#Preview {
    NavigationStack {
        MeasurementResultView(
            result: MeasurementResult(
                bph: 28800, rateSecondsPerDay: 1.8, beatErrorMs: 0.32,
                amplitudeDegrees: 286, confidenceScore: 88, durationSeconds: 30,
                snrDB: 31.4, beatCount: 240, reliabilityNote: nil
            ),
            watch: Watch(brand: "Tudor", model: "Black Bay 58", caliber: "Tudor_MT5602")
        )
    }
    .environment(UserPreferences())
}
