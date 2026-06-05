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
    /// 다중 선택 삭제 모드 — true 면 행 탭이 선택 토글로 동작하고 좌측에 체크박스 표시.
    var selectionMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelect: (() -> Void)? = nil

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

    /// 3-3: 측정 자세 — 행에 조건 병기(자세 다른 측정 혼동 방지). unknown 이면 숨김.
    private var position: Position { measurement.metadata.position }

    var body: some View {
        Button {
            if selectionMode { onToggleSelect?() } else { onTap?() }
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .disabled(!selectionMode && onTap == nil)
        // Round 170: VStack 안에선 swipeActions 가 작동 X → contextMenu 로 개별 삭제 제공.
        .contextMenu {
            if !selectionMode, let onDelete {
                Button(role: .destructive) { onDelete() } label: {
                    Label(String(localized: "common.delete"), systemImage: "trash")
                }
            }
        }
        .accessibilityAddTraits(selectionMode && isSelected ? .isSelected : [])
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            if selectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.ink3)
                    .accessibilityHidden(true)   // 선택 상태는 행 .isSelected trait 로 음성 안내
            }
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
                    if position != .unknown {
                        Text(position.rawValue)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundStyle(AppColors.ink2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(AppColors.paper2)
                            .clipShape(Capsule())
                            .accessibilityLabel(position.localizedName)
                    }
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
            if onTap != nil && !selectionMode {
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
