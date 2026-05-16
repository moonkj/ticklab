import Foundation
import StoreKit

/// $9.99/yr 구독 — TickLab Pro. (사용자 결정: one-time → yearly subscription 으로 변경)
///
/// Free tier 제한:
/// - 시계 등록 최대 1개
/// - 측정 하루 3회
/// - 일기 월 5개
/// - AI Diagnosis trial 3회/시계
/// Pro: 모든 제한 해제 + Share Card 고급 스타일 + Service log 무제한.
@MainActor
final class ProEntitlement: ObservableObject {
    static let shared = ProEntitlement()

    static let productId = "com.ticklab.app.pro.yearly"
    static let freeWatchLimit = 1
    static let freeDailyMeasurementLimit = 3
    static let freeJournalMonthLimit = 5
    static let freeAITrialPerWatch = 3

    @Published private(set) var isPro: Bool = false

    /// Round 15 (Jay): 중복 listener 방지. iPad multi-window scene rebuild 시
    ///   startTransactionListener 가 두 번 호출되면 double-finish 위험.
    private var listenerTask: Task<Void, Never>?

    private init() {
        // UserDefaults 에서 빠른 lookup (UserPreferences.isPro 와 sync).
        self.isPro = UserDefaults.standard.bool(forKey: "ticklab.isPro")
    }

    /// StoreKit 2 transaction listener — app launch 시 한 번 시작. 중복 호출은 no-op.
    func startTransactionListener() {
        guard listenerTask == nil else { return }
        listenerTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        // Round 18 (Doyoon): productID 가 다른 transaction 도 반드시 finish() — 미finish 시
        //   Transaction.updates 가 매 부팅마다 같은 record 를 다시 던져 listener 무한 replay.
        //   App Review 가 unfinished queue 잔존을 거절 사유로 잡는 케이스 있음.
        defer { Task { await transaction.finish() } }
        guard transaction.productID == Self.productId else { return }
        if transaction.revocationDate == nil {
            storeKitMarkPro(true)
        } else {
            storeKitMarkPro(false)
        }
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
