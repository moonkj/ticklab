import SwiftData
import SwiftUI

/// Sprint 1 (P1-4): 시계 등록 후 다음 단계 3-step 체크리스트.
/// WatchDetailView 진입 시 첫 측정/사진/일기 중 하나라도 누락이면 표시.
/// 사용자가 닫기 또는 모든 step 완료 시 영구 숨김 (시계별 UserDefaults flag).
struct NextStepsGuideCard: View {
    let watch: Watch
    @Environment(\.modelContext) private var context
    @State private var dismissed: Bool = false

    private var dismissKey: String { "ticklab.nextsteps.dismissed.\(watch.id.uuidString)" }

    private var hasPhoto: Bool { watch.photoData != nil }
    private var hasMeasurement: Bool { !watch.measurements.isEmpty }
    private var hasWear: Bool {
        WearLogService.wearCount(for: watch, in: context) > 0
    }
    private var completedCount: Int {
        [hasPhoto, hasMeasurement, hasWear].filter { $0 }.count
    }
    private var allCompleted: Bool { completedCount == 3 }

    private var isHidden: Bool {
        dismissed
        || UserDefaults.standard.bool(forKey: dismissKey)
        || allCompleted
    }

    var body: some View {
        if !isHidden {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(String(localized: "watch.nextsteps.title"))
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(AppColors.accentDark)
                    Spacer()
                    Text("\(completedCount)/3")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.ink2)
                    Button {
                        UserDefaults.standard.set(true, forKey: dismissKey)
                        dismissed = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(AppColors.ink3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "common.close"))
                }
                step(done: hasPhoto, title: "watch.nextsteps.photo")
                step(done: hasMeasurement, title: "watch.nextsteps.measure")
                step(done: hasWear, title: "watch.nextsteps.wear")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [AppColors.accent50, AppColors.accent100],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.accent.opacity(0.4), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func step(done: Bool, title: LocalizedStringResource) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(done ? AppColors.success : AppColors.ink3)
            Text(title)
                .font(.system(size: 13, weight: done ? .regular : .semibold))
                .foregroundStyle(done ? AppColors.ink2 : AppColors.ink0)
                .strikethrough(done, color: AppColors.ink3)
            Spacer()
        }
    }
}
