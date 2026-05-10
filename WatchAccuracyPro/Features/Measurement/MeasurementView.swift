import SwiftUI
import SwiftData

struct MeasurementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: MeasurementViewModel
    @State private var startTime: Date?

    init(watch: Watch, preferences: UserPreferences) {
        _viewModel = State(wrappedValue: MeasurementViewModel(watch: watch, preferences: preferences))
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            LiveWaveformView(samples: viewModel.waveformSamples)
                .frame(height: 140)
            metricsGrid
            ConfidenceBadge(score: viewModel.liveMetrics.confidenceScore)
            Spacer()
            switch viewModel.state {
            case .idle:
                PrimaryButton(String(localized: "measurement.button.start")) {
                    Task { await viewModel.start() }
                }
            case .requestingPermission:
                ProgressView(String(localized: "measurement.status.permission_pending"))
            case .measuring:
                PrimaryButton(String(localized: "measurement.button.stop"), style: .bordered) {
                    viewModel.stop(modelContext: modelContext)
                }
            case .completed(let result):
                NavigationLink(value: result) {
                    PrimaryButton(String(localized: "measurement.button.see_result")) {}
                        .allowsHitTesting(false)
                }
            case .failed(let reason):
                permissionFallback(reason: reason)
            }
        }
        .padding(16)
        .navigationTitle(viewModel.watch.model)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: MeasurementResult.self) { result in
            MeasurementResultView(result: result, watch: viewModel.watch)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.watch.brand)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                if let movement = viewModel.movement {
                    Text("\(movement.id) · \(movement.bph) BPH")
                        .font(AppTypography.caption)
                }
            }
            Spacer()
            Text(formatElapsed(viewModel.liveMetrics.elapsedSeconds))
                .font(AppTypography.monoMetric)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private var metricsGrid: some View {
        let lm = viewModel.liveMetrics
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            MetricBadge(
                label: "Rate",
                value: lm.rateSecondsPerDay.map { String(format: "%+.1f", $0) } ?? "—",
                unit: String(localized: "unit.seconds_per_day"),
                tone: rateTone(lm.rateSecondsPerDay)
            )
            MetricBadge(
                label: "Beat Error",
                value: lm.beatErrorMs.map { String(format: "%.2f", $0) } ?? "—",
                unit: "ms"
            )
            MetricBadge(
                label: "Amplitude",
                value: lm.amplitudeDegrees.map { String(format: "%.0f", $0) } ?? "—",
                unit: "°"
            )
            MetricBadge(
                label: "BPH",
                value: lm.bph.map(String.init) ?? "—"
            )
        }
    }

    private func permissionFallback(reason: String) -> some View {
        VStack(spacing: 12) {
            HelpCard(
                icon: "mic.slash",
                title: String(localized: "measurement.permission.title"),
                body: String(localized: "measurement.permission.body"),
                tone: .warning
            )
            if reason == "permission" {
                Button(String(localized: "measurement.permission.openSettings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
            PrimaryButton(String(localized: "common.cancel"), style: .bordered) {
                dismiss()
            }
        }
    }

    private func rateTone(_ rate: Double?) -> MetricBadge.Tone {
        guard let rate else { return .neutral }
        let abs = abs(rate)
        if abs <= 6 { return .success }
        if abs <= 20 { return .warning }
        return .danger
    }

    private func formatElapsed(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

#Preview {
    NavigationStack {
        MeasurementView(
            watch: Watch(brand: "Hamilton", model: "Khaki Field", caliber: "ETA_2824-2"),
            preferences: UserPreferences()
        )
    }
    .modelContainer(for: [Watch.self, WatchMeasurement.self], inMemory: true)
}
