import SwiftUI

struct MeasurementResultView: View {
    let result: MeasurementResult
    let watch: Watch
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if preferences.userMode == .beginner {
                    beginnerSummary
                } else {
                    expertSummary
                }
                if let key = result.reliabilityNoteKey {
                    HelpCard(
                        icon: "info.circle",
                        title: String(localized: "movement.reliability.coaxial.title"),
                        body: String(localized: String.LocalizationValue(key))
                    )
                }
                ConfidenceBadge(score: result.confidenceScore)
                actions
            }
            .padding(16)
        }
        .navigationTitle(String(localized: "result.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Beginner

    private var beginnerSummary: some View {
        VStack(spacing: 12) {
            Text(verdict.emoji)
                .font(.system(size: 80))
            Text(verdict.headline)
                .font(AppTypography.title)
                .multilineTextAlignment(.center)
            Text(verdict.body)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            DisclosureGroup(String(localized: "result.beginner.why")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "result.beginner.detail.rate")
                         + ": " + String(format: "%+.1f s/일", result.rateSecondsPerDay))
                    Text(String(localized: "result.beginner.detail.beat_error")
                         + ": " + String(format: "%.2f ms", result.beatErrorMs))
                    if let amp = result.amplitudeDegrees {
                        Text(String(localized: "result.beginner.detail.amplitude")
                             + ": " + String(format: "%.0f°", amp))
                    }
                    Text(String(localized: "result.beginner.detail.bph")
                         + ": \(result.bph) BPH")
                }
                .font(AppTypography.caption)
                .padding(.top, 8)
            }
            .padding(12)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Expert

    private var expertSummary: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                MetricBadge(
                    label: "Rate", value: String(format: "%+.1f", result.rateSecondsPerDay),
                    unit: String(localized: "unit.seconds_per_day"),
                    tone: rateTone(result.rateSecondsPerDay)
                )
                MetricBadge(
                    label: "Beat Error", value: String(format: "%.2f", result.beatErrorMs),
                    unit: "ms",
                    tone: result.beatErrorMs < 0.5 ? .success : .warning
                )
                MetricBadge(
                    label: "Amplitude",
                    value: result.amplitudeDegrees.map { String(format: "%.0f", $0) } ?? "—",
                    unit: "°"
                )
                MetricBadge(label: "BPH", value: "\(result.bph)")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "result.expert.metadata"))
                    .font(AppTypography.headline)
                LabeledContent(String(localized: "result.duration"), value: "\(result.durationSeconds)s")
                LabeledContent("SNR", value: String(format: "%.1f dB", result.snrDB))
                LabeledContent(String(localized: "result.beat_count"), value: "\(result.beatCount)")
            }
            .padding(12)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            PrimaryButton(String(localized: "result.action.measure_again"), style: .bordered) {
                dismiss()
            }
            // TODO(phase2): 측정 결과 PDF/CSV 공유
        }
    }

    private var verdict: (emoji: String, headline: String, body: String) {
        let abs = abs(result.rateSecondsPerDay)
        if abs <= 10 {
            return ("🟢",
                    String(localized: "result.verdict.ok.title"),
                    String(localized: "result.verdict.ok.body"))
        } else if abs <= 20 {
            return ("🟡",
                    String(localized: "result.verdict.caution.title"),
                    String(localized: "result.verdict.caution.body"))
        } else {
            return ("🔴",
                    String(localized: "result.verdict.service.title"),
                    String(localized: "result.verdict.service.body"))
        }
    }

    private func rateTone(_ rate: Double) -> MetricBadge.Tone {
        let abs = abs(rate)
        if abs <= 6 { return .success }
        if abs <= 20 { return .warning }
        return .danger
    }
}

#Preview {
    NavigationStack {
        MeasurementResultView(
            result: MeasurementResult(
                bph: 28800, rateSecondsPerDay: 7.4, beatErrorMs: 0.4,
                amplitudeDegrees: 285, confidenceScore: 88, durationSeconds: 60,
                snrDB: 32, beatCount: 480, reliabilityNoteKey: nil
            ),
            watch: Watch(brand: "Hamilton", model: "Khaki Field", caliber: "ETA_2824-2")
        )
    }
    .environment(UserPreferences())
}
