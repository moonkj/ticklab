import StoreKit
import SwiftData
import SwiftUI

/// TickLab Pro 페이월 — 월간 / 연간(구독).
/// Free → Pro 업그레이드 진입점. Settings.accountHero 에서 시트로 진입.
struct PurchaseView: View {
    enum Plan { case monthly, yearly }

    @Environment(\.dismiss) private var dismiss
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.purchaseRouter) private var purchaseRouter
    /// Sprint 14 (S6): 개인화 — 최근 7일 측정 횟수.
    @Query private var allMeasurements: [WatchMeasurement]
    /// 스트림B(2): watchLimit intent 프리뷰 — 등록 시계 수/썸네일.
    @Query(sort: \Watch.createdAt, order: .reverse) private var watches: [Watch]

    private var recentMeasureCount: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return allMeasurements.filter { $0.timestamp >= cutoff }.count
    }

    /// 스트림B(2): dailyMeasurement 프리뷰용 — 최근 측정(시간순). rate 스파크라인 입력.
    private var recentMeasurementsForSparkline: [WatchMeasurement] {
        allMeasurements
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(12)
    }

    @State private var monthlyProduct: Product?
    @State private var yearlyProduct: Product?
    @State private var selectedPlan: Plan = .yearly
    @State private var isLoadingProduct = true
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var purchaseError: String?
    @State private var purchaseSuccess = false
    @ScaledMetric(relativeTo: .largeTitle) private var scaledPriceSize: CGFloat = 34
    @ScaledMetric(relativeTo: .title) private var scaledHeadlineSize: CGFloat = 26

    private var selectedProduct: Product? {
        switch selectedPlan {
        case .monthly:  return monthlyProduct
        case .yearly:   return yearlyProduct
        }
    }

    /// 스트림B(1): 선택된 상품의 introductory offer 가 무료 체험(.freeTrial)일 때만 노출.
    /// 실제 trial 설정은 개발자가 ASC 에서 하고, 코드는 offer 유무에 따라 표시만 한다(graceful).
    private var selectedTrialOffer: Product.SubscriptionOffer? {
        guard let offer = selectedProduct?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        return offer
    }

    /// 무료 체험 기간을 사람이 읽는 문자열로(예: "7일"). period.unit + value 를 로컬라이즈.
    /// 단위 문자열은 Foundation 의 ISO 기간 포맷 없이 단순 결합(ASC trial 은 보통 7일/1주).
    private func trialPeriodText(_ offer: Product.SubscriptionOffer) -> String {
        let value = offer.period.value
        let unit: String
        switch offer.period.unit {
        case .day:   unit = String(localized: "paywall.trial.unit.day", defaultValue: "일")
        case .week:  unit = String(localized: "paywall.trial.unit.week", defaultValue: "주")
        case .month: unit = String(localized: "paywall.trial.unit.month", defaultValue: "개월")
        case .year:  unit = String(localized: "paywall.trial.unit.year", defaultValue: "년")
        @unknown default: unit = String(localized: "paywall.trial.unit.day", defaultValue: "일")
        }
        return "\(value)\(unit)"
    }

    /// 연간 결제 할인율 뱃지 — 두 제품 실가격이 모두 로드됐고 실제 할인(>0)이 있을 때만.
    /// 감사 수정: 가짜 가격 폴백(1.99/9.99) 제거 + 토글 버튼에 실제 전달(이전엔 미사용 dead).
    private var yearlyDiscountBadge: String? {
        guard let monthly = monthlyProduct, let yearly = yearlyProduct else { return nil }
        let annualIfMonthly = NSDecimalNumber(decimal: monthly.price).doubleValue * 12
        let yearlyPrice  = NSDecimalNumber(decimal: yearly.price).doubleValue
        guard annualIfMonthly > 0 else { return nil }
        let pct = Int(((annualIfMonthly - yearlyPrice) / annualIfMonthly * 100).rounded())
        guard pct > 0 else { return nil }
        return String(format: String(localized: "purchase.plan.yearly.badge"), pct)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    contextBanner
                    dataPreview
                    hero
                    planToggle
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
            .task { await loadProducts() }
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
            VStack(alignment: .leading, spacing: 6) {
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
                // Sprint 14 (S6): 개인화 — 최근 활동을 보여줘 가치 환기.
                if recentMeasureCount >= 2 {
                    Text(String(format: NSLocalizedString("purchase.context.personalized", comment: ""), recentMeasureCount))
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.ink2)
                }
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

    // MARK: - 스트림B(2): Paywall 데이터 미리보기

    /// intent 별 사용자 본인 데이터 미니 프리뷰 — 손실회피 카피로 가치 환기.
    /// watchLimit → 등록 시계 수/썸네일, dailyMeasurement → 최근 측정 수·rate 스파크라인.
    @ViewBuilder
    private var dataPreview: some View {
        switch purchaseRouter?.lastIntent {
        case .watchLimit:
            if !watches.isEmpty { watchLimitPreview }
        case .dailyMeasurement:
            if !allMeasurements.isEmpty { measurementPreview }
        default:
            EmptyView()
        }
    }

    private var watchLimitPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            previewHeader(
                icon: "rectangle.stack.fill",
                title: String(localized: "paywall.preview.watch.title",
                              defaultValue: "내 컬렉션")
            )
            HStack(spacing: -10) {
                ForEach(watches.prefix(5)) { watch in
                    previewThumb(for: watch)
                }
                if watches.count > 5 {
                    Text("+\(watches.count - 5)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColors.ink2)
                        .frame(width: 36, height: 36)
                        .background(AppColors.paper2)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppColors.paper0, lineWidth: 2))
                }
                Spacer(minLength: 0)
            }
            // 손실회피: 더 등록하려면 잠금이 걸린다는 점을 사실 기반으로 환기(가짜 할인·강요 X).
            Text(String(format: String(localized: "paywall.preview.watch.body",
                                       defaultValue: "%d개의 시계를 기록 중이에요. 무료 등록 한도에 도달했어요."),
                        watches.count))
                .font(.system(size: 12))
                .foregroundStyle(AppColors.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.paper1)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.rule, lineWidth: 1))
    }

    private var measurementPreview: some View {
        let series = recentMeasurementsForSparkline
        return VStack(alignment: .leading, spacing: 10) {
            previewHeader(
                icon: "waveform.path.ecg",
                title: String(localized: "paywall.preview.measure.title",
                              defaultValue: "내 측정 기록")
            )
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(allMeasurements.count)")
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColors.ink0)
                    Text(String(localized: "paywall.preview.measure.count_label",
                                defaultValue: "총 측정"))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(AppColors.ink2)
                }
                if series.count >= 2 {
                    Sparkline(values: series.map(\.rateSecondsPerDay), width: 140, height: 36)
                    Spacer(minLength: 0)
                }
            }
            Text(String(localized: "paywall.preview.measure.body",
                        defaultValue: "오늘 무료 측정 한도에 도달했어요. 무제한으로 계속 추적해 보세요."))
                .font(.system(size: 12))
                .foregroundStyle(AppColors.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.paper1)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.rule, lineWidth: 1))
    }

    private func previewHeader(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.accentDark)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(AppColors.ink2)
            Spacer(minLength: 0)
        }
    }

    private func previewThumb(for watch: Watch) -> some View {
        ZStack {
            if let ui = PhotoCache.image(for: watch.id, data: watch.photoData) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(AppColors.paper2)
                    .frame(width: 36, height: 36)
                    .overlay(WatchSilhouette(watch: watch, size: 24))
            }
        }
        .overlay(Circle().stroke(AppColors.paper0, lineWidth: 2))
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

    private var planToggle: some View {
        HStack(spacing: 0) {
            planToggleButton(.monthly,
                             label: String(localized: "purchase.plan.toggle.monthly"),
                             price: monthlyProduct?.displayPrice ?? "")
            planToggleButton(.yearly,
                             label: String(localized: "purchase.plan.toggle.yearly"),
                             price: yearlyProduct?.displayPrice ?? "",
                             badge: yearlyDiscountBadge)
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.paper1)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.md).stroke(AppColors.rule, lineWidth: 1))
    }

    private func planToggleButton(_ plan: Plan, label: String, price: String?, badge: String? = nil) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedPlan = plan }
        } label: {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppColors.primaryDeep)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AppColors.accentDark)
                            .clipShape(Capsule())
                    }
                }
                if let price {
                    Text(price)
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else if isLoadingProduct {
                    ProgressView().scaleEffect(0.6).tint(selectedPlan == plan ? AppColors.primaryDeep : AppColors.ink3)
                }
            }
            .foregroundStyle(selectedPlan == plan ? AppColors.primaryDeep : AppColors.ink2)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(selectedPlan == plan
                ? LinearGradient(colors: [AppColors.accent, AppColors.accentDark], startPoint: .topLeading, endPoint: .bottomTrailing)
                : LinearGradient(colors: [Color.clear, Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var pricingCard: some View {
        VStack(spacing: 8) {
            let planKey: String = {
                switch selectedPlan {
                case .monthly:  return "purchase.plan.monthly"
                case .yearly:   return "purchase.plan.yearly"
                }
            }()
            Text(String(localized: String.LocalizationValue(planKey)))
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(AppColors.accentDark)

            // 스트림B(1): 무료 체험 offer 가 있으면 "N일 무료 체험 후 ₩X" 배지.
            if let offer = selectedTrialOffer, let price = selectedProduct?.displayPrice {
                Text(String(format: String(localized: "paywall.trial.badge",
                                           defaultValue: "%1$@ 무료 체험 후 %2$@"),
                            trialPeriodText(offer), price))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.primaryDeep)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(AppColors.accentDark)
                    .clipShape(Capsule())
            }

            if isLoadingProduct {
                ProgressView()
                    .tint(AppColors.accentDark)
                    .padding(.vertical, 6)
            } else {
                // StoreKit displayPrice 만 사용 — 하드코드 fallback 제거 (Hard Rule #3 locale 종속 방지).
                // Product 로드 실패 시 빈 텍스트로 두고 retry/restore 로 처리.
                if let displayPrice = selectedProduct?.displayPrice {
                    Text(displayPrice)
                        .font(.system(size: scaledPriceSize, weight: .bold))
                        .foregroundStyle(AppColors.ink0)
                } else {
                    ProgressView()
                        .tint(AppColors.accentDark)
                        .padding(.vertical, 6)
                }
                let perKey: String = {
                    switch selectedPlan {
                    case .monthly:  return "purchase.plan.monthly.per_month"
                    case .yearly:   return "purchase.plan.yearly.per_year"
                    }
                }()
                Text(String(localized: String.LocalizationValue(perKey)))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.ink2)
                let legalKey: String = {
                    switch selectedPlan {
                    case .monthly:  return "purchase.legal.auto_renew.monthly"
                    case .yearly:   return "purchase.legal.auto_renew"
                    }
                }()
                Text(String(localized: String.LocalizationValue(legalKey)))
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                // 스트림B(1): 무료 체험 시 자동청구 전환 안내(법적 — 다크패턴 방지).
                if let offer = selectedTrialOffer {
                    Text(String(format: String(localized: "paywall.trial.legal",
                                               defaultValue: "%@ 무료 체험이 끝나면 자동으로 유료 구독이 시작되며, 언제든 취소할 수 있어요."),
                                trialPeriodText(offer)))
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.ink2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
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
            // 스트림B(1): 무료 체험 offer 있으면 "무료 체험 시작" CTA, 없으면 기존 문구(graceful).
            let ctaTitle: String = {
                if isPurchasing {
                    return String(localized: "purchase.cta.processing")
                }
                if selectedTrialOffer != nil {
                    return String(localized: "paywall.trial.cta", defaultValue: "무료 체험 시작")
                }
                return String(localized: "purchase.cta.subscribe")
            }()
            PrimaryButton(
                ctaTitle,
                style: .accent,
                isEnabled: !isPurchasing && !isRestoring && selectedProduct != nil
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
            let legalKey = "purchase.legal.auto_renew"
            Text(String(localized: String.LocalizationValue(legalKey)))
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

    private func loadProducts() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            let loaded = try await Product.products(for: ProEntitlement.allProductIds)
            for p in loaded {
                if p.id == ProEntitlement.monthlyProductId  { monthlyProduct  = p }
                if p.id == ProEntitlement.yearlyProductId   { yearlyProduct   = p }
            }
        } catch {
            monthlyProduct  = nil
            yearlyProduct   = nil
        }
    }

    private func buy() async {
        guard let product = selectedProduct else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let ok = try await ProEntitlement.shared.purchase(product)
            if ok { purchaseSuccess = true }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        await ProEntitlement.shared.restore()
        // 복원 성공 판정은 realPro(실제 StoreKit 엔타이틀먼트)로 — isPro 는 프로모 기간엔 강제 true 라
        //   구매 없는 사용자도 '복원 성공'으로 오탐(프로모 종료 후 버그). 실제 구매 여부만 본다.
        if ProEntitlement.shared.realPro {
            purchaseSuccess = true
        } else {
            // Apple guideline 3.1.1: Restore 탭 후 사용자에게 명시적 결과 안내 필수.
            //   복원할 구매 없을 때 silent 면 review reject 리스크.
            purchaseError = String(localized: "purchase.restore.none")
        }
    }
}
