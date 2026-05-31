import SwiftUI

/// Sprint 6 (P2-20): 친구 초대 레퍼럴 화면.
struct ReferralView: View {
    @State private var showingShareSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 헤더
                VStack(spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(AppColors.accentDark)
                        .padding(.top, 24)
                    Text(String(localized: "referral.title"))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(AppColors.ink0)
                    Text(String(localized: "referral.subtitle"))
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.ink2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                // 코드 카드
                VStack(spacing: 8) {
                    Text(String(localized: "referral.code.label"))
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(AppColors.accentDark)
                    Text(ReferralService.referralCode)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColors.ink0)
                        .onTapGesture {
                            UIPasteboard.general.string = ReferralService.referralCode
                        }
                    Text(String(localized: "referral.code.tap_to_copy"))
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.ink3)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [AppColors.accent50, AppColors.accent100],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.accent.opacity(0.4), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)

                // 링크 공유 버튼
                ShareLink(item: ReferralService.shareURL,
                          message: Text(String(localized: "referral.share.message"))) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text(String(localized: "referral.share.button"))
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColors.accentDark)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 20)

                // 혜택 안내
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "referral.benefit.title"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.ink0)
                    benefitRow(icon: "clock", text: "referral.benefit.1")
                    benefitRow(icon: "star", text: "referral.benefit.2")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.paper1)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.rule, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)

                Text(String(localized: "referral.disclaimer"))
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.ink3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            }
        }
        .background(AppColors.paper0.ignoresSafeArea())
        .navigationTitle(String(localized: "referral.nav.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func benefitRow(icon: String, text: LocalizedStringResource) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(AppColors.accentDark).frame(width: 20)
            Text(text).font(.system(size: 13)).foregroundStyle(AppColors.ink2)
        }
    }
}
