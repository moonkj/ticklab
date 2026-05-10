import SwiftUI
import Charts

struct TrendChartView: View {
    enum Range: String, CaseIterable, Identifiable {
        case sevenDays = "7d"
        case thirtyDays = "30d"
        var id: String { rawValue }
        var days: Int {
            switch self {
            case .sevenDays: return 7
            case .thirtyDays: return 30
            }
        }
        var label: String {
            switch self {
            case .sevenDays: return String(localized: "trend.range.7d")
            case .thirtyDays: return String(localized: "trend.range.30d")
            }
        }
    }

    let measurements: [WatchMeasurement]
    @State private var range: Range = .sevenDays

    private var filtered: [WatchMeasurement] {
        let cutoff = Date().addingTimeInterval(-Double(range.days) * 86_400)
        return measurements.filter { $0.timestamp >= cutoff }.sorted(by: { $0.timestamp < $1.timestamp })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "trend.title"))
                    .font(AppTypography.headline)
                Spacer()
                Picker("", selection: $range) {
                    ForEach(Range.allCases) { r in
                        Text(r.label).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            if filtered.isEmpty {
                Text(String(localized: "trend.empty"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                    .background(AppColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Chart {
                    ForEach(filtered, id: \.id) { m in
                        PointMark(
                            x: .value("date", m.timestamp),
                            y: .value("rate", m.rateSecondsPerDay)
                        )
                        .foregroundStyle(color(for: m).opacity(0.8))
                        .symbolSize(opacityFromConfidence(m.confidenceScore) * 80)
                    }
                    if filtered.count > 1 {
                        ForEach(filtered, id: \.id) { m in
                            LineMark(
                                x: .value("date", m.timestamp),
                                y: .value("rate", m.rateSecondsPerDay)
                            )
                            .foregroundStyle(AppColors.primary.opacity(0.5))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    RuleMark(y: .value("zero", 0)).foregroundStyle(AppColors.border)
                }
                .frame(height: 180)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
            }
        }
    }

    private func color(for m: WatchMeasurement) -> Color {
        let abs = abs(m.rateSecondsPerDay)
        if abs <= 6 { return AppColors.success }
        if abs <= 20 { return AppColors.warning }
        return AppColors.danger
    }

    private func opacityFromConfidence(_ score: Int) -> Double {
        max(0.3, Double(score) / 100)
    }
}

#Preview {
    let demo = (0..<10).map { idx in
        WatchMeasurement(
            timestamp: Date().addingTimeInterval(-Double(idx) * 86_400),
            rateSecondsPerDay: Double.random(in: -10...10),
            beatErrorMs: Double.random(in: 0.1...0.8),
            amplitudeDegrees: 280,
            bph: 28800,
            confidenceScore: Int.random(in: 60...95),
            durationSeconds: 60
        )
    }
    return TrendChartView(measurements: demo).padding()
}
