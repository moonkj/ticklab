import SwiftUI

/// 측정 결과 진단 카드.
/// Round 160: 실제 Apple Intelligence (FoundationModels) 호출 + 폴백 rule-based.
/// 카드 상단 라벨이 어떤 백엔드인지 표시.
struct AIDiagnosisCard: View {
    let rateSecondsPerDay: Double
    var confidence: Int = 78
    /// Round 160: AI 호출에 필요한 컨텍스트.
    var watch: Watch?
    var movement: Movement?
    var result: MeasurementResult?

    @Environment(UserPreferences.self) private var preferences
    /// shell-level paywall.
    @Environment(\.purchaseRouter) private var purchaseRouter
    @State private var expanded = false
    @State private var serviceVerdict: AppleIntelligenceVerdictService.Verdict?
    @State private var isLoading = true
    /// Free 사용자 AI trial 잔여 — loadVerdict 후 UserDefaults 에서 read.
    @State private var trialsUsed: Int = 0

    enum Tier { case ok, warn, danger
        var color: Color {
            switch self {
            case .ok:     return AppColors.success
            case .warn:   return AppColors.warning
            case .danger: return AppColors.danger
            }
        }
    }

    private var tier: Tier {
        let r = rateSecondsPerDay
        if abs(r) > 12 { return .danger }
        if r > 7 || r < -4 { return .warn }
        return .ok
    }

    /// 표시할 헤드라인 — AI 결과 있으면 그것, 아니면 fallback 한 줄.
    private var displayHeadline: String {
        serviceVerdict?.headline ?? fallbackHeadline
    }
    private var displayBody: String {
        serviceVerdict?.body ?? fallbackBody
    }
    /// VoiceOver 용 신뢰도 등급. 색상으로만 전달되던 정보를 음성으로도 전달.
    private var confidenceGradeLabel: String {
        if confidence >= 80 { return String(localized: "aidiag.confidence.grade.high") }
        if confidence >= 60 { return String(localized: "aidiag.confidence.grade.medium") }
        return String(localized: "aidiag.confidence.grade.low")
    }
    private var isAI: Bool {
        serviceVerdict?.source == .appleIntelligence
    }

    private var fallbackHeadline: String {
        switch tier {
        case .ok:     return String(localized: "aidiag.fallback.ok.headline")
        case .warn:   return String(localized: "aidiag.fallback.warn.headline")
        case .danger: return String(localized: "aidiag.fallback.danger.headline")
        }
    }
    private var fallbackBody: String {
        switch tier {
        case .ok:     return String(localized: "aidiag.fallback.ok.body")
        case .warn:   return String(localized: "aidiag.fallback.warn.body")
        case .danger: return String(localized: "aidiag.fallback.danger.body")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sourceBadge
            Text(displayHeadline)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppColors.ink0)
            Text(displayBody)
                .font(.system(size: 15))
                .foregroundStyle(AppColors.ink2)

            HStack(spacing: 8) {
                Text(String(localized: isAI ? "aidiag.confidence.ai" : "aidiag.confidence.rule"))
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(AppColors.ink2)
                // UX 감사: 5-segment 대신 단일 continuous bar (가로 공간 절약 + 직관적).
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppColors.rule).frame(height: 6)
                        Capsule()
                            .fill(LinearGradient(
                                colors: [AppColors.warning, AppColors.success],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * CGFloat(confidence) / 100, height: 6)
                    }
                }
                .frame(width: 100, height: 6)
                // Round 104 (A11y Critical): VoiceOver 가 bar 값 읽도록.
                .accessibilityHidden(true)
                Spacer()
                Text("\(confidence)%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.ink0)
                    // 사용자 보고 fix: VoiceOver 가 신뢰도 등급(높음/중간/낮음) 발화 추가.
                    .accessibilityLabel(String(format: String(localized: "aidiag.confidence.a11y"), confidence))
                    .accessibilityValue(confidenceGradeLabel)
            }
            .padding(.top, 4)

            Button { withAnimation { expanded.toggle() } } label: {
                HStack(spacing: 6) {
                    Text(String(localized: expanded ? "aidiag.expand.expanded" : "aidiag.expand.collapsed"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.accentDark)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.accentDark)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(Text(expanded ? String(localized: "a11y.disclosure.expanded") : String(localized: "a11y.disclosure.collapsed")))

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "aidiag.causes.title"))
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(AppColors.ink2)
                    ForEach(Array(causes.enumerated()), id: \.offset) { idx, cause in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(idx + 1).")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppColors.ink2)
                            Text(cause)
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.ink0)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.paper2)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.info)
                Text(String(localized: isAI ? "aidiag.disclaimer.ai" : "aidiag.disclaimer.rule"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.primaryDeep)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.info.opacity(0.08))
            .overlay(Rectangle().fill(AppColors.info).frame(width: 4), alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            // 사용자 보고 fix: Free 사용자 AI trial 상태 안내 + 소진 시 upgrade CTA. 다른 한도들과 일관.
            trialFootnote
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.paper1)
        .overlay(Rectangle().fill(tier.color).frame(width: 4), alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.rule, lineWidth: 1))
        .task { await loadVerdict() }
    }

    /// Free 사용자 전용: AI trial 잔여 안내. 소진 시 업그레이드 CTA.
    @ViewBuilder
    private var trialFootnote: some View {
        if !preferences.isPro && watch != nil {
            let limit = ProEntitlement.freeAITrialPerWatch
            let remaining = max(0, limit - trialsUsed)
            if remaining == 0 {
                Button {
                    purchaseRouter?.intend(.aiTrial)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                        Text(String(localized: "aidiag.trial.exhausted_cta"))
                            .font(.system(size: 12, weight: .semibold))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(AppColors.accentDark)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(AppColors.accent50)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            } else if isAI {
                Text(String(format: NSLocalizedString("aidiag.trial.remaining", comment: ""), remaining, limit))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppColors.ink3)
            }
        }
    }

    /// AI / rule-based 출처 라벨.
    private var sourceBadge: some View {
        HStack(spacing: 4) {
            if isLoading {
                ProgressView().scaleEffect(0.6)
                Text(String(localized: "aidiag.source.loading"))
            } else {
                Image(systemName: isAI ? "sparkles" : "function")
                    .font(.system(size: 10))
                Text(String(localized: isAI ? "aidiag.source.ai" : "aidiag.source.rule"))
            }
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .tracking(1)
        .foregroundStyle(isAI ? AppColors.accentDark : AppColors.ink2)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(isAI ? AppColors.accent50 : AppColors.paper2)
        .clipShape(Capsule())
    }

    private var filledBars: Int { Int(round(Double(confidence) / 20.0)) }

    private var causes: [String] {
        switch tier {
        case .ok:
            return [String(localized: "aidiag.cause.ok.1"),
                    String(localized: "aidiag.cause.ok.2")]
        case .warn:
            return [String(localized: "aidiag.cause.warn.1"),
                    String(localized: "aidiag.cause.warn.2"),
                    String(localized: "aidiag.cause.warn.3")]
        case .danger:
            return [String(localized: "aidiag.cause.danger.1"),
                    String(localized: "aidiag.cause.danger.2"),
                    String(localized: "aidiag.cause.danger.3")]
        }
    }

    @MainActor
    private func loadVerdict() async {
        guard let watch, let result else {
            isLoading = false
            return
        }
        // Round 80: 사용자가 AI 진단 OFF 면 즉시 rule-based fallback.
        guard preferences.aiVerdictEnabled else {
            serviceVerdict = AppleIntelligenceVerdictService.shared.fallbackVerdict(for: result)
            isLoading = false
            return
        }
        // 사용자 결정: Free 사용자는 시계별 AI Diagnosis 3회 trial. 초과 시 rule-based fallback.
        //   Trial 카운트는 UserDefaults 의 watch.id 별 key. Pro 무제한.
        // 사용자 보고 fix: 이전엔 AI 호출 *전에* used+1 했음 → 결과 화면 진입/회전마다 +1 → Free 유저
        //   1~2 세션이면 quota 소진. 변경: (1) 같은 measurement.id 는 이미 카운트 했으면 재충전 X.
        //   (2) AI verdict 가 실제로 돌아오면 그 때 카운트.
        let trialKey = "ticklab.aiTrial.\(watch.id.uuidString)"
        // Dedup 키: 같은 측정 (rate/beatCount/duration 동일) 은 결과 화면 재진입해도 1회만 차감.
        //   hashValue 는 런타임 랜덤화 되어서 stable 한 field 조합으로 키 생성.
        let dedupKey = "\(watch.id.uuidString).\(result.bph).\(String(format: "%.4f", result.rateSecondsPerDay)).\(result.beatCount).\(result.durationSeconds)"
        let consumedKey = "ticklab.aiTrial.consumed.\(dedupKey)"
        let alreadyConsumed = UserDefaults.standard.bool(forKey: consumedKey)
        let usedBefore = UserDefaults.standard.integer(forKey: trialKey)
        trialsUsed = usedBefore
        if !preferences.isPro {
            if !alreadyConsumed && usedBefore >= ProEntitlement.freeAITrialPerWatch {
                serviceVerdict = AppleIntelligenceVerdictService.shared.fallbackVerdict(for: result)
                isLoading = false
                return
            }
        }
        // Round 78: AI 호출 5초 timeout — 무한 로딩 방지.
        // Round 82: 토글 명시 전달 — service 단 게이트 작동 보장.
        let aiEnabled = preferences.aiVerdictEnabled
        let verdictTask = Task { @MainActor in
            await AppleIntelligenceVerdictService.shared.verdict(
                for: result, watch: watch, movement: movement, aiEnabled: aiEnabled
            )
        }
        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            return AppleIntelligenceVerdictService.shared.fallbackVerdict(for: result)
        }
        // 둘 중 먼저 끝나는 것 사용. verdictTask 가 빠르면 timeoutTask cancel.
        // Round 17 (Hyemi): group.cancelAll 은 group wrapper 만 취소 — verdictTask/timeoutTask 자체는
        //   detached 라 cancel 안 됨 → LLM 호출이 timeout 후에도 백그라운드에서 계속 진행됐던 leak.
        //   명시적으로 두 task 다 cancel 하여 Apple Intelligence 세션 점유 해제.
        let v: AppleIntelligenceVerdictService.Verdict = await {
            await withTaskGroup(of: AppleIntelligenceVerdictService.Verdict.self) { group in
                group.addTask { await verdictTask.value }
                group.addTask { await timeoutTask.value }
                let first = await group.next() ?? AppleIntelligenceVerdictService.shared.fallbackVerdict(for: result)
                group.cancelAll()
                verdictTask.cancel()
                timeoutTask.cancel()
                return first
            }
        }()
        serviceVerdict = v
        isLoading = false
        // Trial 카운트: AI 가 실제로 verdict 반환했고 (rule-fallback 아닐 때) Free 유저면 +1.
        //   같은 measurement 면 한 번만 차감.
        if !preferences.isPro,
           v.source == .appleIntelligence,
           !UserDefaults.standard.bool(forKey: consumedKey) {
            let used = UserDefaults.standard.integer(forKey: trialKey)
            UserDefaults.standard.set(used + 1, forKey: trialKey)
            UserDefaults.standard.set(true, forKey: consumedKey)
            trialsUsed = used + 1
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        AIDiagnosisCard(rateSecondsPerDay: 5.2, confidence: 92)
        AIDiagnosisCard(rateSecondsPerDay: 9.0, confidence: 78)
    }
    .padding()
    .background(AppColors.paper0)
}
