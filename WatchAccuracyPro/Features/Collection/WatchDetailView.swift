import SwiftUI
import SwiftData

struct WatchDetailView: View {
    @Bindable var watch: Watch
    @Environment(UserPreferences.self) private var preferences

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroImage
                titleBlock
                infoCard
                if let movement, !movement.shouldDisplayAmplitude {
                    HelpCard(
                        icon: "info.circle",
                        title: String(localized: "movement.reliability.coaxial.title"),
                        body: String(localized: "movement.reliability.coaxial.notice")
                    )
                }
                NavigationLink {
                    MeasurementView(watch: watch, preferences: preferences)
                } label: {
                    PrimaryButton(String(localized: "watch.cta.measure")) {}
                        .allowsHitTesting(false)
                }

                if !watch.measurements.isEmpty {
                    historySection
                }
            }
            .padding(16)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var movement: Movement? {
        guard let caliber = watch.caliber else { return nil }
        return MovementDatabase.shared.movement(id: caliber)
    }

    private var heroImage: some View {
        Group {
            if let data = watch.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "stopwatch")
                    .font(.system(size: 64))
                    .foregroundStyle(AppColors.textMuted)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 220)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(watch.brand)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            Text(watch.model).font(AppTypography.title)
            if let caliber = watch.caliber {
                Text(caliber)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var infoCard: some View {
        if let movement, preferences.userMode == .expert {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "watch.info.movement_specs"))
                    .font(AppTypography.headline)
                HStack {
                    InfoPill(label: "BPH", value: "\(movement.bph)")
                    InfoPill(label: "Lift", value: "\(Int(movement.liftAngleDegrees))°")
                    InfoPill(label: "Escapement", value: movement.escapement.rawValue)
                }
            }
            .padding(14)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "watch.history.title"))
                .font(AppTypography.headline)

            ForEach(watch.measurements.sorted(by: { $0.timestamp > $1.timestamp }).prefix(10), id: \.id) { m in
                HStack {
                    VStack(alignment: .leading) {
                        Text(m.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                        Text(formatRate(m.rateSecondsPerDay))
                            .font(AppTypography.body)
                            .monospaced()
                    }
                    Spacer()
                    Text("\(m.confidenceScore)")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(confidenceColor(m.confidenceScore).opacity(0.15))
                        .foregroundStyle(confidenceColor(m.confidenceScore))
                        .clipShape(Capsule())
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func formatRate(_ rate: Double) -> String {
        let sign = rate >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", rate)) s/d"
    }

    private func confidenceColor(_ score: Int) -> Color {
        switch score {
        case 80...:   return AppColors.success
        case 50..<80: return AppColors.warning
        default:      return AppColors.danger
        }
    }
}

private struct InfoPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(AppTypography.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        WatchDetailView(
            watch: Watch(brand: "Omega", model: "Seamaster", caliber: "Omega_8800")
        )
    }
    .modelContainer(for: [Watch.self, WatchMeasurement.self], inMemory: true)
    .environment(UserPreferences())
}
