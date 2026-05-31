import SwiftUI

/// 커뮤니티 첫 게시 전 약관 동의 — UGC zero-tolerance(App Store Guideline 1.2 필수).
/// 동의해야 게시 가능. 동의는 1회 저장(`CommunityService.acceptEULA`).
struct CommunityEULAView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = CommunityService.shared
    let onAgree: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "community.eula.title"))
                        .font(AppTypography.title)
                        .foregroundStyle(AppColors.ink0)
                    Text(String(localized: "community.eula.body"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(rules, id: \.self) { key in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.accentDark)
                            Text(String(localized: String.LocalizationValue(key)))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.ink1)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(24)
            }
            .background(AppColors.paper0)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    PrimaryButton(String(localized: "community.eula.agree")) {
                        // 수락 처리는 caller 가 결정(뷰어 동의 vs 게시 동의 분리 — Round 3 컴플라이언스).
                        onAgree()
                        dismiss()
                    }
                    Button(String(localized: "common.cancel")) { dismiss() }
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.ink2)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(AppColors.paper0)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private let rules = [
        "community.eula.rule.zero_tolerance",
        "community.eula.rule.no_others",
        "community.eula.rule.report",
    ]
}
