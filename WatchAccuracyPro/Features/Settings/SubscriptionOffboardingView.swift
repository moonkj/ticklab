import SwiftData
import SwiftUI

/// Sprint 2 (P1-7): 구독 해지 retention sheet.
/// Pro 사용자가 "구독 관리" 진입 직전 표시 — 데이터 요약 + 잃게 될 기능 + 2 CTA.
/// Apple Review 가이드 권장 패턴: 사용자에게 데이터/기능 가치 명시 후 해지 결정.
struct SubscriptionOffboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var watches: [Watch]
    @Query private var measurements: [WatchMeasurement]
    @Query private var journals: [JournalEntry]
    /// 부모가 dismiss 직후 manageSubscriptionsSheet 띄울 수 있도록 콜백.
    let onProceedToManage: () -> Void

    private var firstWatchDate: Date? {
        watches.map(\.createdAt).min()
    }

    private var daysSinceFirstWatch: Int {
        guard let first = firstWatchDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: first, to: Date()).day ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    hero
                    summaryCard
                    whatYoullLose
                    ctaButtons
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(AppColors.paper0.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.close")) { dismiss() }
                }
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(AppColors.accent.opacity(0.4)).frame(width: 88, height: 88).blur(radius: 16)
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(AppColors.accentDark)
            }
            .padding(.top, 16)
            Text(String(localized: "offboarding.title"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppColors.ink0)
                .multilineTextAlignment(.center)
            Text(String(localized: "offboarding.subtitle"))
                .font(.system(size: 14))
                .foregroundStyle(AppColors.ink2)
                .multilineTextAlignment(.center)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "offboarding.summary.title"))
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(AppColors.accentDark)
            HStack(spacing: 18) {
                statColumn(value: watches.count, label: "offboarding.summary.watches")
                Divider().frame(height: 36)
                statColumn(value: measurements.count, label: "offboarding.summary.measurements")
                Divider().frame(height: 36)
                statColumn(value: journals.count, label: "offboarding.summary.journals")
            }
            if daysSinceFirstWatch > 0 {
                Text(String(format: NSLocalizedString("offboarding.summary.days", comment: ""), daysSinceFirstWatch))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink2)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [AppColors.accent50, AppColors.accent100],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.accent.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func statColumn(value: Int, label: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                // 타이포 SSOT: 숫자=monospaced 통일 (이전 rounded → mono).
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColors.ink0)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.ink2)
        }
    }

    private var whatYoullLose: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "offboarding.lose.title"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.ink0)
            loseRow("offboarding.lose.unlimited_watches")
            loseRow("offboarding.lose.unlimited_measurements")
            loseRow("offboarding.lose.unlimited_ai")
            loseRow("offboarding.lose.data_retained")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.paper1)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func loseRow(_ key: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.warning)
                .padding(.top, 1)
            Text(key)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var ctaButtons: some View {
        VStack(spacing: 10) {
            PrimaryButton(
                String(localized: "offboarding.cta.keep"),
                style: .accent,
                isEnabled: true
            ) {
                dismiss()
            }
            Button {
                dismiss()
                // 부모 dismiss 애니메이션 후 manage sheet 진입.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onProceedToManage()
                }
            } label: {
                Text(String(localized: "offboarding.cta.manage"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.ink2)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
        }
    }
}
