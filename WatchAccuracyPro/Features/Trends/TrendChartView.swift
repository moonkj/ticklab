import SwiftUI
import Charts

// MARK: - TrendRange

/// 트렌드 차트 기간 선택. WatchDetailView + TrendChartView 가 공유.
enum WatchDetailTrendRange: String, CaseIterable {
    case week = "7d", month = "30d", quarter = "90d", year = "1y", all = "ALL"

    var cutoffDate: Date {
        switch self {
        case .week:    return Date().addingTimeInterval(-7 * 86400)
        case .month:   return Date().addingTimeInterval(-30 * 86400)
        case .quarter: return Date().addingTimeInterval(-90 * 86400)
        case .year:    return Date().addingTimeInterval(-365 * 86400)
        case .all:     return .distantPast
        }
    }

    var days: Int {
        switch self {
        case .week: return 7; case .month: return 30; case .quarter: return 90
        case .year: return 365; case .all: return 9999
        }
    }
}

/// Round 73: 외부 컨테이너(WatchDetailView)의 range picker 가 이미 filter 한 measurements 를 받아 그리는 dumb presenter.
/// Round 171: range 전달 → chartXScale domain + chartXAxis label 이 range 에 맞게 고정.
/// 이전엔 x-axis 가 data 범위에만 맞춰져 range 바꿔도 날짜가 안 바뀌는 버그.
struct TrendChartView: View {
    let measurements: [WatchMeasurement]
    /// range = nil 이면 데이터 범위에 맞춤 (ALL 케이스 호환).
    var range: WatchDetailTrendRange?

    private var sorted: [WatchMeasurement] {
        measurements.sorted(by: { $0.timestamp < $1.timestamp })
    }

    private var xDomain: ClosedRange<Date> {
        let end = Date()
        guard let r = range else {
            let start = sorted.first?.timestamp ?? end.addingTimeInterval(-7 * 86400)
            return start...end
        }
        switch r {
        case .all:
            let start = sorted.first?.timestamp ?? end.addingTimeInterval(-7 * 86400)
            return start...end
        default:
            return r.cutoffDate...end
        }
    }

    var body: some View {
        Chart {
            if sorted.isEmpty {
                // 데이터 없어도 x-axis 날짜는 range 에 맞게 표시 — 투명 anchor point 로 domain 강제.
                PointMark(x: .value("date", xDomain.lowerBound), y: .value("rate", 0.0))
                    .foregroundStyle(.clear)
                PointMark(x: .value("date", xDomain.upperBound), y: .value("rate", 0.0))
                    .foregroundStyle(.clear)
            } else {
                ForEach(sorted, id: \.id) { m in
                    PointMark(
                        x: .value("date", m.timestamp),
                        y: .value("rate", m.rateSecondsPerDay)
                    )
                    .foregroundStyle(color(for: m).opacity(0.8))
                    .symbolSize(opacityFromConfidence(m.confidenceScore) * 80)
                }
                if sorted.count > 1 {
                    ForEach(sorted, id: \.id) { m in
                        LineMark(
                            x: .value("date", m.timestamp),
                            y: .value("rate", m.rateSecondsPerDay)
                        )
                        .foregroundStyle(AppColors.primary.opacity(0.5))
                        .interpolationMethod(.catmullRom)
                    }
                }
            }
            RuleMark(y: .value("zero", 0)).foregroundStyle(AppColors.border)
        }
        .chartXScale(domain: xDomain)
        .chartXAxis { xAxisContent as AnyAxisContent }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .overlay {
            if sorted.isEmpty {
                Text(String(localized: "trend.empty"))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private var xAxisContent: AnyAxisContent {
        switch range ?? .week {
        case .week:
            return AnyAxisContent(AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
            })
        case .month:
            return AnyAxisContent(AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
            })
        case .quarter:
            return AnyAxisContent(AxisMarks(values: .stride(by: .month, count: 1)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            })
        case .year:
            return AnyAxisContent(AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            })
        case .all:
            // 실제 데이터 span 에 맞게 granularity 자동 조정.
            let spanDays = sorted.isEmpty ? 0 : {
                let s = sorted.first!.timestamp
                let e = sorted.last!.timestamp
                return Int(e.timeIntervalSince(s) / 86400)
            }()
            if spanDays <= 14 {
                return AnyAxisContent(AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                })
            } else if spanDays <= 60 {
                return AnyAxisContent(AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                })
            } else if spanDays <= 365 {
                return AnyAxisContent(AxisMarks(values: .stride(by: .month, count: 1)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                })
            } else {
                return AnyAxisContent(AxisMarks(values: .stride(by: .month, count: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                })
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
    TrendChartView(measurements: demo, range: .month).padding()
}
