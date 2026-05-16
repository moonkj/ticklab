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
        // 사용자 보고 fix: defer { Task { ... } } 가 finish 를 fire-and-forget 으로 던져서 같은 transaction 이
        //   Transaction.updates 로 재 delivery 될 수 있는 race. await 로 동기 처리.
        if transaction.productID == Self.productId {
            if transaction.revocationDate == nil {
                storeKitMarkPro(true)
            } else {
                storeKitMarkPro(false)
            }
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
        var foundActiveEntitlement = false
        for await result in Transaction.currentEntitlements {
            // 활성 entitlement 가 우리 productID 인지 검사 (revocation 검출용).
            if case .verified(let transaction) = result,
               transaction.productID == Self.productId,
               transaction.revocationDate == nil {
                foundActiveEntitlement = true
            }
            await handle(result)
        }
        // 사용자 보고 fix: 환불/구독 만료 시 currentEntitlements 에 우리 productID 없음 → silent
        //   하게 isPro=true 유지하던 버그. 활성 entitlement 없으면 명시적으로 false 처리.
        if !foundActiveEntitlement {
            storeKitMarkPro(false)
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
        // 사용자 보고 fix: 같은 상태 중복 set 방지 — Transaction.updates 와 purchase() 가 같은 tx 를
        //   모두 처리해 중복 notification post 되던 race 차단.
        guard isPro != on else { return }
        isPro = on
        UserDefaults.standard.set(on, forKey: "ticklab.isPro")
        // Round 149 (Hyemi 7 H1): UserPreferences 인스턴스 갱신 — observer 들이 즉시 반응.
        NotificationCenter.default.post(name: .ticklabProEntitlementChanged, object: nil, userInfo: ["isPro": on])
    }
}
