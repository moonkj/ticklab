import StoreKit
import SwiftUI

/// TickLab Pro 연 9.99$ 구독 페이월.
/// Free → Pro 업그레이드 진입점. Settings.accountHero 에서 시트로 진입.
struct PurchaseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UserPreferences.self) private var preferences
    /// 어떤 한도가 트리거됐는지 PurchaseView 가 알아서 context banner 표시.
    @Environment(\.purchaseRouter) private var purchaseRouter

    @State private var product: Product?
    @State private var isLoadingProduct = true
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var purchaseError: String?
    @State private var purchaseSuccess = false
    /// 사용자 보고 fix: 가격 텍스트 Dynamic Type — 시각 장애 / 노안 사용자 가격 정보 인지 보장.
    @ScaledMetric(relativeTo: .largeTitle) private var scaledPriceSize: CGFloat = 34
    @ScaledMetric(relativeTo: .title) private var scaledHeadlineSize: CGFloat = 26

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    contextBanner
                    hero
                    benefitsList
                    pricingCard
                    actionButtons
                    legalLinks
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(AppColors.paper0.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            // 사용자 보고 fix: 글로벌 indigo tint 가 PurchaseView 의 gold brand 와 충돌 → tint(accent) 로 override.
            .tint(AppColors.accentDark)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.close")) { dismiss() }
                }
            }
            .task { await loadProduct() }
            .alert(String(localized: "purchase.error.title"),
                   isPresented: Binding(get: { purchaseError != nil },
                                        set: { if !$0 { purchaseError = nil } })) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(purchaseError ?? "")
            }
            .alert(String(localized: "purchase.success.title"),
                   isPresented: $purchaseSuccess) {
                Button(String(localized: "common.ok"), role: .cancel) { dismiss() }
            } message: {
                Text(String(localized: "purchase.success.body"))
            }
        }
    }

    /// 한도 트리거 사유 banner — settings 에서 직접 진입한 경우는 안 보임.
    @ViewBuilder
    private var contextBanner: some View {
        if let key = purchaseRouter?.lastIntent?.contextKey {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.info)
                Text(String(localized: String.LocalizationValue(key)))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.ink0)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppColors.info.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppColors.info.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppColors.accent.opacity(0.5))
                    .frame(width: 110, height: 110)
                    .blur(radius: 22)
                LinearGradient(
                    colors: [AppColors.accent, AppColors.accentDark],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(width: 88, height: 88)
                .clipShape(Circle())
                Image(systemName: "sparkles")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(AppColors.primaryDeep)
            }
            .padding(.top, 16)

            Text(String(localized: "purchase.headline"))
                .font(.system(size: scaledHeadlineSize, weight: .bold))
                .foregroundStyle(AppColors.ink0)
                .multilineTextAlignment(.center)

            Text(String(localized: "purchase.subtitle"))
                .font(.system(size: 14))
                .foregroundStyle(AppColors.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    private var benefitsList: some View {
        VStack(alignment: .leading, spacing: 14) {
            benefitRow(icon: "infinity",
                       title: String(localized: "purchase.benefit.unlimited_watches.title"),
                       body: String(localized: "purchase.benefit.unlimited_watches.body"))
            benefitRow(icon: "waveform.path.ecg",
                       title: String(localized: "purchase.benefit.unlimited_measurements.title"),
                       body: String(localized: "purchase.benefit.unlimited_measurements.body"))
            benefitRow(icon: "book.pages",
                       title: String(localized: "purchase.benefit.unlimited_journal.title"),
                       body: String(localized: "purchase.benefit.unlimited_journal.body"))
            benefitRow(icon: "brain.head.profile",
                       title: String(localized: "purchase.benefit.unlimited_ai.title"),
                       body: String(localized: "purchase.benefit.unlimited_ai.body"))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.paper1)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .stroke(AppColors.rule, lineWidth: 1)
        )
    }

    private func benefitRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.accentDark)
                .frame(width: 26, height: 26)
                .background(AppColors.accent50)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.ink0)
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.ink2)
            }
        }
    }

    private var pricingCard: some View {
        VStack(spacing: 8) {
            Text(String(localized: "purchase.plan.yearly"))
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(AppColors.accentDark)

            if isLoadingProduct {
                // 사용자 보고 fix: 글로벌 indigo tint 가 gold 배경에 indigo 점 → tint(accentDark) override.
                ProgressView()
                    .tint(AppColors.accentDark)
                    .padding(.vertical, 6)
            } else if let product {
                Text(product.displayPrice)
                    .font(.system(size: scaledPriceSize, weight: .bold))
                    .foregroundStyle(AppColors.ink0)
                Text(String(localized: "purchase.plan.yearly.per_year"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink2)
                // Apple Schedule 2: 가격/주기/자동갱신 안내가 CTA 위에 함께 노출되어야 함.
                Text(String(localized: "purchase.legal.auto_renew"))
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
            } else {
                // StoreKit 미연결/sandbox 미설정 시 — 하드코딩 가격 표시 X (non-USD storefront 오해 방지).
                //   안내 + 재시도만 노출. Subscribe CTA 는 product==nil 일 때 disabled.
                Text(String(localized: "purchase.unavailable"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.warning)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                Button {
                    Task { await loadProduct() }
                } label: {
                    Label(String(localized: "purchase.retry"), systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.accentDark)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            LinearGradient(
                colors: [AppColors.accent50, AppColors.accent100],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .stroke(AppColors.accent.opacity(0.4), lineWidth: 1)
        )
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            PrimaryButton(
                isPurchasing
                    ? String(localized: "purchase.cta.processing")
                    : String(localized: "purchase.cta.subscribe"),
                style: .accent,
                isEnabled: !isPurchasing && !isRestoring && product != nil
            ) {
                Task { await buy() }
            }

            Button {
                Task { await restore() }
            } label: {
                Text(isRestoring
                     ? String(localized: "purchase.cta.restoring")
                     : String(localized: "purchase.cta.restore"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.ink2)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .disabled(isPurchasing || isRestoring)
        }
    }

    private var legalLinks: some View {
        VStack(spacing: 6) {
            Text(String(localized: "purchase.legal.auto_renew"))
                .font(.system(size: 11))
                .foregroundStyle(AppColors.ink3)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link(destination: URL(string: "https://moonkj.github.io/ticklab/terms.html")!) {
                    Text(String(localized: "purchase.legal.terms"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.ink2)
                }
                Link(destination: URL(string: "https://moonkj.github.io/ticklab/privacy.html")!) {
                    Text(String(localized: "purchase.legal.privacy"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.ink2)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - StoreKit

    private func loadProduct() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            let products = try await Product.products(for: [ProEntitlement.productId])
            product = products.first
        } catch {
            // Sandbox 미연결이면 nil 유지 — fallback 가격 표시.
            product = nil
        }
    }

    private func buy() async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let ok = try await ProEntitlement.shared.purchase()
            if ok {
                purchaseSuccess = true
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        await ProEntitlement.shared.restore()
        // 사용자 보고 fix: UserPreferences.isPro 는 NotificationCenter 이벤트 비동기 → race.
        //   ProEntitlement.shared.isPro 를 직접 read (StoreKit 검증 후 즉시 set 됨).
        if ProEntitlement.shared.isPro {
            purchaseSuccess = true
        } else {
            // Apple guideline 3.1.1: Restore 탭 후 사용자에게 명시적 결과 안내 필수.
            //   복원할 구매 없을 때 silent 면 review reject 리스크.
            purchaseError = String(localized: "purchase.restore.none")
        }
    }
}
