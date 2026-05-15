import SwiftUI

struct MeasurementResultView: View {
    let result: MeasurementResult
    let watch: Watch
    /// Round 133: 부모(MeasurementView) 가 state 를 .idle 로 reset 후 dismiss 하도록 콜백 주입.
    /// 없으면 단순 dismiss (sheet/standalone 으로 쓰는 경우).
    var onRetry: (() -> Void)? = nil
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    private var movement: Movement? {
        watch.caliber.flatMap { MovementDatabase.shared.movement(id: $0) }
    }

    /// 신호 품질(신뢰도·박동오차)은 양호한데 rate 가 비정상적으로 크면
    /// 측정 오류(알고리즘 잘못된 주기 lock)일 가능성이 높음 → 재측정 권장.
    private var isSuspiciousMeasurement: Bool {
        abs(result.rateSecondsPerDay) > 30
        && result.confidenceScore >= 50
        && result.beatErrorMs < 2.0
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
                if preferences.userMode == .novice, watch.measurements.isEmpty {
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
                .font(.system(size: 44, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
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
            let headlineSize: CGFloat = isHighConfidenceGrade ? 28 : 32
            let bodySize: CGFloat = isHighConfidenceGrade ? 14 : 15
            Text("\u{201C}\(verdict.headline).\u{201D}")
                .font(.system(size: headlineSize, weight: .semibold, design: .serif))
                .foregroundStyle(verdict.toneColor)
                .lineSpacing(2)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            Text(verdict.body)
                .font(.system(size: bodySize, weight: isHighConfidenceGrade ? .regular : .medium))
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
        let bigFont: CGFloat = isHighConfidenceGrade ? 60 : 38
        let bigColor: Color = isHighConfidenceGrade ? verdict.toneColor : AppColors.ink2
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
                Text(String(localized: "unit.seconds_per_day"))
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundStyle(AppColors.ink2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rate \(formatRate(result.rateSecondsPerDay)) \(String(localized: "unit.seconds_per_day"))")
            // Round 170: 측정 신뢰도 오차 ±X s/d — rate 아래 작게.
            if let rateUncertainty = rateUncertaintyString {
                Text(rateUncertainty)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppColors.ink3)
            }
            RateDial(rate: result.rateSecondsPerDay, size: 220)
                .padding(.top, 4)
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

    private func amplitudeHint() -> String {
        guard let amp = result.amplitudeDegrees else {
            return movement?.escapement == .coAxial
                ? String(localized: "result.amplitude.coaxial") : ""
        }
        // Round 99 (최용수 Critical #2): movement DB 의 typicalAmplitudeRange 를 임계 기준으로 사용.
        // DB 에 없으면 modern Swiss 기본값 (270/220) 적용.
        let minHealthy: Double = movement?.typicalAmplitudeMin ?? 270.0
        let minBorderline: Double = minHealthy - 50.0
        if amp >= minHealthy { return String(localized: "result.amplitude.healthy") }
        if amp >= minBorderline { return String(localized: "result.amplitude.borderline") }
        return String(localized: "result.amplitude.service")
    }

    // MARK: - Details (expert mode)

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            EyebrowLabel(text: String(localized: "result.section.details"), number: "02")
            VStack(spacing: 0) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    SpecRow(label: String(localized: "result.label.duration"),
                            value: "\(result.durationSeconds) s")
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
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if let onRetry { onRetry() } else { dismiss() }
            } label: {
                Label(String(localized: "result.suspicious.retry"), systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.warning)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppColors.warning.opacity(0.12))
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
            PrimaryButton(String(localized: "result.action.save"), style: .accent) {
                // Round 170: onRetry 호출만 — 부모 state .idle → navigationDestination(item:) 가 자동으로
                // result view pop. 추가 dismiss() 시 NavigationStack 한 단계 더 pop 돼 WatchDetailView 로
                // 가버리는 race 차단.
                if let onRetry { onRetry() } else { dismiss() }
            }
            HStack(spacing: 10) {
                PrimaryButton(String(localized: "result.action.again"), style: .bordered) {
                    // Round 170: 재측정 — onRetry 만 호출. cancel() 이 state .idle 로 reset 하면
                    // navigationDestination(item:) 가 result view 자동 pop → MeasurementView 정확히 도착.
                    // 추가 dismiss() 호출하면 NavigationStack 이 한 단계 더 pop (WatchDetailView 까지 가는 버그).
                    if let onRetry { onRetry() } else { dismiss() }
                }
                Button {
                    showShareCard = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18))
                        .foregroundStyle(AppColors.ink2)
                        .frame(width: 48, height: 48)
                        .background(AppColors.paper2)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
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
