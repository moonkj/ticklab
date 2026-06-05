import SwiftUI

/// 신기능 안내(what's-new) — 발견성 강화.
/// UX 진단(R1, 3직군 합의): 업데이트로 추가된 기능을 기존 사용자에게 알리는 in-app 채널이 0건 →
///   "영영 모름". 버전당 1회 비강제 바텀시트로 노출하고, 닫으면 영구 숨김.
/// 신규 사용자는 온보딩 완료 시점에 현재 버전으로 캐치업해 이 시트를 보지 않는다.
enum WhatsNew {
    /// 카탈로그 버전 — 신기능 묶음이 바뀔 때만 올린다(MARKETING_VERSION 과 독립).
    static let version = "1.0.2"

    struct Item: Identifiable {
        let id = UUID()
        let icon: String
        let titleKey: String.LocalizationValue
        let bodyKey: String.LocalizationValue
    }

    /// 이번 릴리스에서 추가된, 발견성이 낮은 기능들 (위치 안내 포함).
    static let items: [Item] = [
        Item(icon: "scope",
             titleKey: "whatsnew.positional.title",
             bodyKey: "whatsnew.positional.body"),
        Item(icon: "waveform.path.ecg",
             titleKey: "whatsnew.trend.title",
             bodyKey: "whatsnew.trend.body"),
        Item(icon: "heart",
             titleKey: "whatsnew.wishlist.title",
             bodyKey: "whatsnew.wishlist.body"),
        Item(icon: "wrench.and.screwdriver",
             titleKey: "whatsnew.care.title",
             bodyKey: "whatsnew.care.body"),
    ]

    /// 온보딩 완료 + 아직 이 버전 안내를 안 본 경우에만 노출.
    static func shouldShow(_ prefs: UserPreferences) -> Bool {
        guard prefs.hasCompletedOnboarding else { return false }
        guard !items.isEmpty else { return false }
        return prefs.lastSeenWhatsNewVersion != version
    }

    static func markSeen(_ prefs: UserPreferences) {
        prefs.lastSeenWhatsNewVersion = version
    }
}

/// what's-new 바텀시트 — AppTypography 토큰 기반(신규 코드 토큰 강제 권고 반영).
struct WhatsNewSheet: View {
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 헤더
                VStack(alignment: .leading, spacing: 8) {
                    EyebrowLabel(text: String(localized: "whatsnew.title"))
                    Text(String(localized: "whatsnew.subtitle"))
                        .font(AppTypography.title)
                        .foregroundStyle(AppColors.ink0)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 28)
                .padding(.bottom, 20)

                // 기능 목록
                VStack(spacing: 16) {
                    ForEach(WhatsNew.items) { item in
                        WhatsNewRow(item: item)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(AppColors.paper0)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(String(localized: "whatsnew.dismiss")) {
                dismiss()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(AppColors.paper0)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // 표시되는 순간 = "봤다"로 기록 (스와이프로 닫아도 다시 안 뜨도록).
        .onAppear { WhatsNew.markSeen(preferences) }
    }
}

private struct WhatsNewRow: View {
    let item: WhatsNew.Item

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppColors.accentTint)
                    .frame(width: 44, height: 44)
                ConceptGlyph(systemName: item.icon, size: 18, color: AppColors.accentDark)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: item.titleKey))
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.ink0)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: item.bodyKey))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(AppColors.paper1)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .stroke(AppColors.rule, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            WhatsNewSheet()
                .environment(UserPreferences())
        }
}
