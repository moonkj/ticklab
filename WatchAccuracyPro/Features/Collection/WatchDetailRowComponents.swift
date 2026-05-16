import SwiftData
import SwiftUI

/// Round (잔여 분할): WatchDetailView 의 private struct (HistoryRow, StatBlock) 분리.
/// Round 24 (Hyemi): WatchMeasurement Identifiable conformance 는 모델 레이어 (WatchMeasurement.swift) 로 이동.

struct HistoryRow: View {
    let measurement: WatchMeasurement
    let isLast: Bool
    /// Round 29 (Doyoon): tap → note editor sheet. nil 이면 비활성.
    var onTap: (() -> Void)? = nil
    /// Round 170: swipe-to-delete.
    var onDelete: (() -> Void)? = nil

    private var tone: Color {
        let abs = abs(measurement.rateSecondsPerDay)
        if abs <= 6 { return AppColors.success }
        if abs <= 20 { return AppColors.warning }
        return AppColors.danger
    }

    private var hasNote: Bool {
        guard let n = measurement.notes else { return false }
        return !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        // Round 170: VStack 안에선 swipeActions 가 작동 X → contextMenu 로 개별 삭제 제공.
        .contextMenu {
            if let onDelete {
                Button(role: .destructive) { onDelete() } label: {
                    Label(String(localized: "common.delete"), systemImage: "trash")
                }
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            Rectangle().fill(tone).frame(width: 4, height: 30).clipShape(Capsule())
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(formatRate(measurement.rateSecondsPerDay))
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(tone)
                    Text(String(localized: "unit.seconds_per_day"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AppColors.ink3)
                }
                HStack(spacing: 6) {
                    Text(formatTimestamp(measurement.timestamp))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(AppColors.ink3)
                    if hasNote {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 10))
                            .foregroundStyle(AppColors.accent)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Chip("\(measurement.confidenceScore)",
                     tone: measurement.confidenceScore >= 80 ? .success
                        : measurement.confidenceScore >= 50 ? .warning : .danger,
                     small: true)
                Text(String(format: "%.2fms", measurement.beatErrorMs))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(AppColors.ink3)
            }
            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColors.ink3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(AppColors.rule).frame(height: 1)
            }
        }
    }

    private func formatTimestamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f.string(from: d).uppercased()
    }
}

// MARK: - StatBlock helper

struct StatBlock: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(AppColors.ink2)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 17, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppColors.ink0)
                Text(unit)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(AppColors.ink3)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
