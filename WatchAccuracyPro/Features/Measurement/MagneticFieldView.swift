import SwiftUI
import Charts

/// Round 180 (Sora) — 주변 자기장 측정 화면.
/// CMMagnetometer 로 약 3초간 sampling → median uT 값 + 등급 + Apple Intelligence 멘트.
/// 진입: TodayView 의 "자기장 체크" 카드 (UserPreferences.magneticFieldMeasurementEnabled 시).
struct MagneticFieldView: View {
    @Environment(UserPreferences.self) private var preferences

    @ObservedObject private var service = MagneticFieldService.shared

    @State private var measuredMicroTesla: Double?
    @State private var level: MagneticFieldService.Level?
    @State private var verdict: AppleIntelligenceVerdictService.Verdict?
    @State private var isMeasuring: Bool = false
    @State private var verdictTask: Task<Void, Never>?
    @State private var measureTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                measureButton
                // Round 137 사용자 요청: 측정 중·완료 시 실시간 sample 그래프.
                if isMeasuring || !service.sampleHistory.isEmpty {
                    liveChartCard
                }
                if let level, let measuredMicroTesla {
                    resultCard(uT: measuredMicroTesla, level: level)
                    verdictCard(level: level)
                }
                infoCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(AppColors.paper0.ignoresSafeArea())
        .navigationTitle(String(localized: "magnetic.title"))
        // Round 138 사용자 요청: 기록/통계처럼 inline 고정 — 스크롤해도 제목 사라지지 않음.
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppColors.paper0, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .onDisappear {
            measureTask?.cancel()
            verdictTask?.cancel()
            service.cancelSampling()
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "magnetic.title"))
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(AppColors.ink0)
            Text(String(localized: "magnetic.header.subtitle"))
                .font(.system(size: 13))
                .foregroundStyle(AppColors.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(LinearGradient(
            colors: [AppColors.accent50, AppColors.paper1],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.rule, lineWidth: 1))
    }

    // MARK: - Measure Button

    private var measureButton: some View {
        Button {
            startMeasurement()
        } label: {
            HStack(spacing: 10) {
                if isMeasuring {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(isMeasuring
                     ? String(localized: "magnetic.measuring")
                     : String(localized: "magnetic.measure_button"))
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(.white)
            .background(AppColors.ink0)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isMeasuring || !service.isAvailable)
        .opacity(service.isAvailable ? 1.0 : 0.5)
    }

    // MARK: - Result Card

    private func resultCard(uT: Double, level: MagneticFieldService.Level) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.0f", uT))
                    .font(.system(size: 48, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.ink0)
                Text("μT")
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppColors.ink2)
                Spacer()
                levelBadge(level)
            }
            Divider()
                .background(AppColors.rule)
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.ink3)
                Text(String(localized: "magnetic.result.earthfield_note"))
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.ink3)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.paper1)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
    }

    private func levelBadge(_ level: MagneticFieldService.Level) -> some View {
        let (fg, bg) = colorPair(for: level)
        return Text(NSLocalizedString(level.localizationKey, comment: ""))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(bg)
            .clipShape(Capsule())
    }

    private func colorPair(for level: MagneticFieldService.Level) -> (Color, Color) {
        switch level {
        case .normal:       return (AppColors.success, AppColors.successTint)
        case .slightlyHigh: return (AppColors.warning, AppColors.warningTint)
        case .high:         return (AppColors.danger, AppColors.dangerTint)
        case .veryHigh:     return (.white, AppColors.danger)
        }
    }

    // MARK: - Verdict (Apple Intelligence)

    private func verdictCard(level: MagneticFieldService.Level) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: verdict?.source == .appleIntelligence ? "sparkles" : "lightbulb")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.accentDark)
                Text(verdict?.source == .appleIntelligence
                     ? String(localized: "magnetic.verdict.label.ai")
                     : String(localized: "magnetic.verdict.label.tip"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.ink2)
            }
            if let v = verdict {
                Text(v.headline)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                if !v.body.isEmpty {
                    Text(v.body)
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(String(localized: "magnetic.verdict.loading"))
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.ink3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColors.paper1)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
    }

    // MARK: - Live Chart (Round 137)

    private var liveChartCard: some View {
        let samples = service.sampleHistory
        // Round 138 BUG FIX (사용자 보고: 낮은 값 측정 후 바로 높은 값 재측정 시 그래프 멈춘 듯 보임):
        // yMax 와 current 를 이전 측정의 currentMicroTesla 가 아닌 *현재* sampleHistory 만으로 계산.
        // 새 측정 시작 직후엔 samples 가 비어 있으니 기본값(150 μT, 지구 자기장 약간 위) 사용.
        let current: Double = samples.last ?? 0
        let peak: Double = samples.max() ?? 0
        let yMax = max(150.0, peak * 1.15)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "magnetic.chart.title"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.ink2)
                Spacer()
                if isMeasuring {
                    HStack(spacing: 4) {
                        Circle().fill(AppColors.danger).frame(width: 6, height: 6)
                        Text(String(localized: "magnetic.chart.live"))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppColors.danger)
                    }
                } else {
                    Text(String(format: "%.0f μT", current))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.ink2)
                }
            }
            Chart {
                ForEach(Array(samples.enumerated()), id: \.offset) { idx, value in
                    LineMark(
                        x: .value("Sample", idx),
                        y: .value("μT", value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(AppColors.accentDark)
                    AreaMark(
                        x: .value("Sample", idx),
                        y: .value("μT", value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(
                        colors: [AppColors.accent.opacity(0.35), AppColors.accent.opacity(0.0)],
                        startPoint: .top, endPoint: .bottom
                    ))
                }
                // 등급 임계선 — 100 / 300 / 1000.
                RuleMark(y: .value("Normal", 100))
                    .foregroundStyle(AppColors.success.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                RuleMark(y: .value("High", 300))
                    .foregroundStyle(AppColors.warning.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .chartYScale(domain: 0...yMax)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(AppColors.rule.opacity(0.4))
                    AxisTick()
                    AxisValueLabel().font(.system(size: 9, design: .monospaced))
                }
            }
            .frame(height: 140)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.paper1)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
    }

    // MARK: - Info Card

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "magnetic.info.title"))
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(AppColors.ink2)
            Text(String(localized: "magnetic.info.body"))
                .font(.system(size: 13))
                .foregroundStyle(AppColors.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.paper2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.rule, lineWidth: 1))
    }

    // MARK: - Actions

    private func startMeasurement() {
        guard !isMeasuring else { return }
        // Round 142 (Min 3 H1): outer measureTask 도 cancel — 빠르게 두 번 탭 시 outer 두 개 leak 방지.
        measureTask?.cancel()
        verdictTask?.cancel()
        verdict = nil
        isMeasuring = true

        measureTask = Task { @MainActor in
            // Round 138 사용자 요청: 측정 시간 3초 → 5초.
            let sampled = await service.sample(durationSeconds: 5.0)
            isMeasuring = false
            guard let value = sampled else {
                // magnetometer 미지원. UI 는 disabled 상태로 안내.
                measuredMicroTesla = nil
                level = nil
                return
            }
            let lvl = MagneticFieldService.level(microTesla: value)
            measuredMicroTesla = value
            level = lvl

            // 즉시 rule-based 폴백 표시 → AI verdict 가 오면 교체.
            let fallback = AppleIntelligenceVerdictService.shared.ruleBasedMagneticVerdict(level: lvl)
            verdict = fallback

            verdictTask = Task { @MainActor in
                let v = await AppleIntelligenceVerdictService.shared.magneticVerdict(
                    microTesla: value,
                    level: lvl,
                    aiEnabled: preferences.aiVerdictEnabled
                )
                if !Task.isCancelled {
                    verdict = v
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        MagneticFieldView()
            .environment(UserPreferences())
    }
}
