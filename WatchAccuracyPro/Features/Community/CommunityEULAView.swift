import SwiftUI

/// 커뮤니티 첫 게시 전 약관 동의 — UGC zero-tolerance(App Store Guideline 1.2 필수).
/// 동의해야 게시 가능. 동의는 1회 저장(`CommunityService.acceptEULA`).
struct CommunityEULAView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = CommunityService.shared
    /// true 면 읽기전용(상시 가이드라인 보기) — 동의/취소 대신 '닫기'만 노출. 기본 false(첫 동의).
    var reviewOnly: Bool = false
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
                    // App Store Guideline 1.2: UGC 신고·문의 연락처를 커뮤니티 동의 흐름 안에 노출.
                    Link(destination: URL(string: "mailto:imurmkj@naver.com?subject=TickLab%20Community%20Report")!) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "envelope")
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.accentDark)
                            Text(String(localized: "community.eula.contact"))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.accentDark)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(24)
            }
            .background(AppColors.paper0)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if reviewOnly {
                        PrimaryButton(String(localized: "common.close")) { dismiss() }
                    } else {
                        PrimaryButton(String(localized: "community.eula.agree")) {
                            // 수락 처리는 caller 가 결정(뷰어 동의 vs 게시 동의 분리 — Round 3 컴플라이언스).
                            onAgree()
                            dismiss()
                        }
                        Button(String(localized: "common.cancel")) { dismiss() }
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.ink2)
                    }
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
        // Hard Rule #8: 사진 데이터 처리 고지를 약관 1회 동의에 포함(게시 화면엔 미노출 — 인스타식).
        "community.photo.consent",
        "community.eula.rule.report",
    ]
}
