import Foundation
import StoreKit

/// $9.99 one-time IAP — TickLab Pro.
/// Pivot Hard Rule: Subscription 금지, one-time only.
///
/// Free tier 제한:
/// - 워치 최대 2개
/// - 일기 월 5개
/// - AI Diagnosis trial 3회/시계
/// Pro: 모든 제한 해제 + Share Card 고급 스타일 + Service log 무제한.
///
/// Phase 1: Stub. Phase 2 에서 StoreKit 2 product fetch + purchase 흐름 구현.
@MainActor
final class ProEntitlement: ObservableObject {
    static let shared = ProEntitlement()

    static let productId = "com.ticklab.app.pro.lifetime"
    static let freeWatchLimit = 2
    static let freeJournalMonthLimit = 5
    static let freeAITrialPerWatch = 3

    @Published private(set) var isPro: Bool = false

    private init() {
        // UserDefaults 에서 빠른 lookup (UserPreferences.isPro 와 sync).
        self.isPro = UserDefaults.standard.bool(forKey: "ticklab.isPro")
    }

    /// StoreKit 2 transaction listener — app launch 시 한 번 시작.
    func startTransactionListener() {
        Task {
            for await update in Transaction.updates {
                await handle(update)
            }
        }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result,
              transaction.productID == Self.productId else { return }
        if transaction.revocationDate == nil {
            storeKitMarkPro(true)
        } else {
            storeKitMarkPro(false)
        }
        await transaction.finish()
    }

    /// Purchase entry — Phase 2 에 PurchaseView 가 호출.
    func purchase() async throws -> Bool {
        let products = try await Product.products(for: [Self.productId])
        guard let product = products.first else { return false }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            await handle(verification)
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async {
        for await result in Transaction.currentEntitlements {
            await handle(result)
        }
    }

    /// Round 149 (Hyemi 7 C4): release 빌드에 internal 노출은 attack surface — DEBUG 전용 외부 set.
    /// Phase 2 StoreKit transaction handler 는 private storeKitMarkPro 사용.
    #if DEBUG
    @MainActor
    func markPro(_ on: Bool) {
        storeKitMarkPro(on)
    }
    #endif

    /// StoreKit 검증된 transaction 만 호출 — private.
    @MainActor
    private func storeKitMarkPro(_ on: Bool) {
        isPro = on
        UserDefaults.standard.set(on, forKey: "ticklab.isPro")
        // Round 149 (Hyemi 7 H1): UserPreferences 인스턴스 갱신 — observer 들이 즉시 반응.
        NotificationCenter.default.post(name: .ticklabProEntitlementChanged, object: nil, userInfo: ["isPro": on])
    }
}
