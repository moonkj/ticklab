import SwiftUI

struct WatchRowView: View {
    let watch: Watch

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(watch.brand)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                Text(watch.model)
                    .font(AppTypography.headline)
                    .lineLimit(1)
                if let lastMeasurement {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.textSecondary)
                        Text(rateText(lastMeasurement.rateSecondsPerDay))
                            .font(AppTypography.caption)
                            .foregroundStyle(rateTone(lastMeasurement.rateSecondsPerDay))
                    }
                } else {
                    Text(String(localized: "watch.row.never_measured"))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textMuted)
                }
            }
            Spacer()
            if let lastMeasurement {
                ConfidenceMiniBadge(score: lastMeasurement.confidenceScore)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var lastMeasurement: WatchMeasurement? {
        watch.measurements.sorted(by: { $0.timestamp > $1.timestamp }).first
    }

    private var thumbnail: some View {
        Group {
            if let data = watch.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "stopwatch.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(width: 56, height: 56)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func rateText(_ rate: Double) -> String {
        let sign = rate >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", rate)) \(String(localized: "unit.seconds_per_day"))"
    }

    private func rateTone(_ rate: Double) -> Color {
        let abs = abs(rate)
        if abs <= 6 { return AppColors.success }
        if abs <= 20 { return AppColors.warning }
        return AppColors.danger
    }
}

private struct ConfidenceMiniBadge: View {
    let score: Int

    var body: some View {
        Text("\(score)")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch score {
        case 80...:   return AppColors.success
        case 50..<80: return AppColors.warning
        default:      return AppColors.danger
        }
    }
}
