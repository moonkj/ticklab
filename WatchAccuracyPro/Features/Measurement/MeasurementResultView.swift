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
    /// 핵심 readout(rate 값+단위) Dynamic Type 대응 — 기준값=기존 크기 → 기본 설정에선 변화 없음, 큰글씨에서만 확대.
    @ScaledMetric(relativeTo: .largeTitle) private var rateValueSizeHigh: CGFloat = 60
    @ScaledMetric(relativeTo: .largeTitle) private var rateValueSizeLow: CGFloat = 28
    @ScaledMetric(relativeTo: .title3) private var rateUnitSize: CGFloat = 16
    /// Round 23 (Doyoon): onAppear haptic 가 매 reentry (share sheet dismiss 등) 마다 fire 하던 버그.
    @State private var didFireHaptic = false
    /// Sprint 12 (UX2): 용어 설명 바텀시트.
    @State private var glossaryEntry: GlossaryEntryID?

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
    /// Round 171 Phase B (전원 재감사 후 정직화): 표시 ± 는 **fit 정밀도 ⊕ 재현성** 의 결합.
    ///   - fitUnc: 단일 윈도우 OLS slope 불확도(residual 기반) — "얼마나 정밀하게 쟀나".
    ///   - reproUnc: 독립 sub-window rate spread/2 — "다시 재면 같은 값이 나오나".
    /// 둘을 제곱합으로 결합 → sub-window 들이 흩어진(불안정) 측정은 ± 가 자동으로 넓어져
    /// "±0.2 인데 사실 30 틀림" 식 과신 표시를 차단한다.
    private var rateUncertaintyString: String? {
        guard let rms = result.residualRMSSeconds, result.beatCount > 1 else { return nil }
        let n = Double(result.beatCount)
        let period = 3600.0 / Double(result.bph)
        let fitUnc = rms * 12.0.squareRoot() / pow(n, 1.5) / period * 86400.0
        let reproUnc = (result.crossWindowRateDelta ?? 0) / 2.0   // spread → σ 근사
        let uncertainty = (fitUnc * fitUnc + reproUnc * reproUnc).squareRoot()
        guard uncertainty.isFinite, uncertainty < 100 else { return nil }
        return String(format: "±%.1f s/d", uncertainty)
    }

    private var verdict: (toneColor: Color, tone: Chip.Tone, headline: String, body: String) {
        let absRate = abs(result.rateSecondsPerDay)
        // 페르소나 (정수민) 피드백: 1회 측정으로 "서비스 권장" 은 감정적 과장.
        // 측정 회수 < 3 이면 service verdict 대신 caution + "한 번 더 측정 권장".
        // Round 169: SwiftData reactive 로 인해 watch.measurements 가 이미 현재 측정 포함된 경우 double-count 방지.
        let measurementCount = max(1, watch.measurements.count)
        let grade = result.reliabilityGrade
        // Round 171 C2 (사용자 보고: grade B 인데 "정비사 가라" 모순):
        // verdict 가 신뢰도를 존중. 신뢰 낮은 측정(C/F)은 *시계 상태*를 단정하지 않고
        // "측정 자체가 불안정 → 다시 측정" 으로 안내 (오염 측정으로 '정비사' 단정 방지).
        if grade == .c || grade == .f {
            return (AppColors.warning, .warning,
                    String(localized: "result.verdict.unreliable.title"),
                    String(localized: "result.verdict.unreliable.body"))
        }
        // Round 142 (Hyemi 4 H1 BUG): success cutoff 다른 화면 (CollectionView/WatchDetailView 등) <=6 인데
        // 여기만 <=10 이었음 — 같은 측정이 list 에선 warning, hero verdict 에선 success 모순. 6 으로 통일.
        if absRate <= 6 {
            return (AppColors.success, .success,
                    String(localized: "result.verdict.ok.title"),
                    String(localized: "result.verdict.ok.body"))
        } else if absRate <= 20 {
            return (AppColors.warning, .warning,
                    String(localized: "result.verdict.caution.title"),
                    String(localized: "result.verdict.caution.body"))
        } else if grade == .b || measurementCount < 3 {
            // Round 171 C2: 중간 신뢰(B) 또는 측정 누적 부족 — 큰 rate 라도 '정비사' 단정 대신 재측정 권장.
            return (AppColors.warning, .warning,
                    String(localized: "result.verdict.first_anomaly.title"),
                    String(localized: "result.verdict.first_anomaly.body"))
        } else {
            // grade A(고신뢰) + |rate|>20 + 측정 누적 충분 → 비로소 "정비사" 단정.
            return (AppColors.danger, .danger,
                    String(localized: "result.verdict.service.title"),
                    String(localized: "result.verdict.service.body"))
        }
    }

    // MARK: - Round 171 다회 측정 평균 (신뢰 대표값)

    /// 이 시계 최근 측정의 MAD outlier 제거 평균. 측정 3회 미만이면 nil.
    /// Round 173 (사용자 지적): **신뢰도 높은 측정만** 평균에 사용 — C/F(노이즈) 측정이 평균을 오염시키지 않도록.
    /// grade 는 저장 안 되므로 confidence+|rate| 로 재계산(spread penalty 없는 상한 — 보수적으로 포함).
    /// 신뢰도 A 가 3개 이상이면 A 만, 부족하면 A/B 로 완화(그래도 C/F 는 항상 제외). 둘 다 부족하면 nil.
    private var recentTrusted: RateAggregate.Trusted? {
        let recent = watch.measurements
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(8)
        let gradeA = recent.filter { gradeOf($0) == .a }.prefix(5)
        let chosen: [WatchMeasurement]
        if gradeA.count >= 3 {
            chosen = Array(gradeA)                                  // 사용자 요청: A 만
        } else {
            chosen = Array(recent.filter { let g = gradeOf($0); return g == .a || g == .b }.prefix(5))  // A 부족 → A/B (C/F 제외)
        }
        // Round 173 self-heal: 각 측정을 현재 클록 보정으로 환산해 epoch 혼재 제거(옛 cal+0 측정도 일관).
        let rates = chosen.map { healedRate($0) }
        return RateAggregate.trusted(rates: rates)
    }

    /// 저장된 측정 rate 를 **현재** 클록 보정 기준으로 환산. (현재ppm − 측정시점ppm)×0.0864 만큼 이동.
    /// 측정시점 ppm 미저장(옛 측정)은 0(cal+0)으로 간주 — 정확.
    private func healedRate(_ m: WatchMeasurement) -> Double {
        let storedPpm = m.metadata.clockCalPpmAtMeasure ?? 0
        let currentPpm = ClockCalibrationService.shared.driftPpm
        return m.rateSecondsPerDay + (currentPpm - storedPpm) * 0.0864
    }

    /// 저장된 측정의 신뢰도 등급 재계산(grade 미저장 — confidence+|rate| 기반). cross-window penalty 는 미보유라
    /// 실제 grade 의 상한(보수적 포함). C/F 만 확실히 걸러내는 용도.
    private func gradeOf(_ m: WatchMeasurement) -> ReliabilityGrade {
        ReliabilityGrade.from(confidence: m.confidenceScore, crossWindowDelta: nil,
                              rateSecondsPerDay: m.rateSecondsPerDay)
    }

    private func recentAverageDetail(_ t: RateAggregate.Trusted) -> String {
        if t.excluded > 0 {
            return String(format: String(localized: "result.recent_avg.detail_trimmed"), t.count, t.spread, t.excluded)
        }
        return String(format: String(localized: "result.recent_avg.detail"), t.count, t.spread)
    }

    @ViewBuilder private var recentAverageCard: some View {
        if let t = recentTrusted {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "result.recent_avg.title"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.accentDark)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%+.1f", t.meanRate))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.ink0)
                    Text("s/d")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.ink3)
                }
                Text(recentAverageDetail(t))
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.ink2)
                Text(String(localized: "result.recent_avg.hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AppColors.accent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                #if DEBUG
                // (DEBUG 진단) 추정기 내부값 — 고정 시계 run-to-run 변동 원인 추적. 릴리스 미표시.
                if let diag = result.diagnostic {
                    Text(diag)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.accentDark)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.accent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                #endif
                // Round 171 (사용자 요청 레이아웃): '이 시계 최근 평균'(신뢰 대표값)을 최상단으로 —
                //   단일 측정보다 평균이 신뢰값. 그 아래 측정 데이터(RATE), 그 아래 해석(신뢰도·verdict).
                recentAverageCard
                // === 측정 데이터 ===
                rateDialCard
                // Round 45 — 디자인 SSOT COSC bar 추가 (rateDial 후).
                COSCBar(rate: result.rateSecondsPerDay)
                    .padding(.horizontal, 4)
                // Sprint 3 (P2-5): 정확도 등급 칩 — COSC/우수/보통/정비 권장.
                AccuracyGradeChip(rateSecondsPerDay: result.rateSecondsPerDay)
                    .padding(.top, 2)
                metricsSection
                if preferences.userMode == .pro { detailsSection }

                // === 해석 블록 (측정 데이터 아래로 이동) ===
                // Round 129 (실기기 피드백): 저장 완료 확인 배너 — AI 스피너와 혼동 방지.
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.success)
                        .font(.system(size: 14))
                        .accessibilityHidden(true)  // 접근성: 옆 텍스트가 의미 전달 — 장식용 아이콘
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
                // Round 172: 기기 시계 자동 보정 안내 — 사용할수록 baseline 이 쌓여 정확도↑.
                HStack(spacing: 6) {
                    Image(systemName: ClockCalibrationService.shared.isCalibrated ? "checkmark.seal.fill" : "clock.arrow.2.circlepath")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.accent)
                    Text(String(localized: ClockCalibrationService.shared.isCalibrated
                                ? "result.calibration.calibrated" : "result.calibration.calibrating"))
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.ink2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 10)
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
        // Sprint 12 (UX2): 메트릭 라벨 탭 → 용어 설명 바텀시트.
        .sheet(item: $glossaryEntry) { e in
            GlossaryDetailSheet(key: e.key, descKey: e.descKey, icon: e.icon)
        }
        .onAppear {
            // Round 23 (Doyoon): 최초 1회만 haptic. share sheet 닫고 reentry 시 재발화 차단.
            guard !didFireHaptic else { return }
            didFireHaptic = true
            // T-17: 햅틱 설정 토글 존중.
            if HapticManager.isEnabled {
                let gen = UINotificationFeedbackGenerator()
                switch result.reliabilityGrade {
                case .a, .b:    gen.notificationOccurred(.success)
                case .c:        gen.notificationOccurred(.warning)
                case .f, .none: UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            // Sprint 1 (P1-6): 골든 모멘트 — 신뢰도 A/B + confidence ≥80 일 때만 카운트.
            // 누적 3회 도달 + 60일 cooldown 통과 시 시스템 리뷰 prompt.
            if let g = result.reliabilityGrade, (g == .a || g == .b), result.confidenceScore >= 80 {
                ReviewRequestService.qualifyingMomentReached()
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
        // 접근성: 등급 타일(글자)·eyebrow·claim·gloss 를 하나의 요소로 묶어 "신뢰도, A, ..." 로 읽힘.
        .accessibilityElement(children: .combine)
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
            // Sprint 12 (UX5): 입문자용 "사람말" 환산 — ±s/d를 주/월 단위로.
            if isHighConfidenceGrade {
                Text(plainLanguageRate)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink2)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    /// Sprint 12 (UX5): ±s/d → "일주일에 약 X초 / 한 달에 약 Y초" 평이한 표현.
    private var plainLanguageRate: String {
        let perDay = result.rateSecondsPerDay
        let absDay = abs(perDay)
        let week = absDay * 7
        let direction = perDay >= 0
            ? String(localized: "result.plain.fast")
            : String(localized: "result.plain.slow")
        if absDay < 0.1 {
            return String(localized: "result.plain.perfect")
        }
        if week < 60 {
            return String(format: NSLocalizedString("result.plain.week_sec", comment: ""), Int(week.rounded()), direction)
        }
        let month = absDay * 30
        return String(format: NSLocalizedString("result.plain.month_min", comment: ""), month / 60, direction)
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
        let bigFont: CGFloat = isHighConfidenceGrade ? rateValueSizeHigh : rateValueSizeLow
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
                    .font(.system(size: rateUnitSize, design: .monospaced))
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
                // 접근성: rate 값은 위 readout 에서 이미 음성 안내됨 — 다이얼은 시각 전용 장식
                .accessibilityHidden(true)
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
                big: true,
                onGlossaryTap: { glossaryEntry = .init(key: "glossary.beat_error", descKey: "glossary.beat_error.desc", icon: "waveform") }
            ),
            MetricBadge(
                label: String(localized: "watch.spec.bph"),
                value: "\(result.bph)",
                hint: movement?.escapement.rawValue.uppercased() ?? NSLocalizedString("result.escapement.fallback", comment: ""),
                big: true,
                onGlossaryTap: { glossaryEntry = .init(key: "glossary.bph", descKey: "glossary.bph.desc", icon: "metronome") }
            ),
            MetricBadge(
                label: String(localized: "confidence.label"),
                value: "\(result.confidenceScore)",
                hint: String(format: NSLocalizedString("result.snr_beats_hint", comment: ""),
                             result.snrDB, result.beatCount),
                tone: result.confidenceScore >= 80 ? .success : .warning,
                big: true,
                onGlossaryTap: { glossaryEntry = .init(key: "glossary.confidence", descKey: "glossary.confidence.desc", icon: "chart.bar.fill") }
            )
        ]
        return VStack(alignment: .leading, spacing: 10) {
            EyebrowLabel(text: String(localized: "result.section.metrics"), number: "01")
            MetricGrid(cells: cells)
            confidenceHelpCard
        }
    }

    /// T-02: 신뢰도<70 이면 저하 원인별 개선 안내(1장으로 통합 — 동일 제목 반복 방지).
    @ViewBuilder private var confidenceHelpCard: some View {
        if result.confidenceScore < 70 {
            let reasons = ConfidenceScorer.reasons(
                snrDB: result.snrDB,
                durationSeconds: Double(result.durationSeconds),
                confidenceScore: result.confidenceScore
            )
            if !reasons.isEmpty {
                HelpCard(
                    icon: "lightbulb",
                    title: String(localized: "confidence.reason.title"),
                    body: reasons
                        .map { String(localized: String.LocalizationValue($0.localizationKey)) }
                        .joined(separator: "\n\n"),
                    tone: .warning
                )
                .padding(.top, 4)
            }
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
                    .accessibilityHidden(true)  // 접근성: 옆 제목 텍스트가 의미 전달 — 장식용 아이콘
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
