import Foundation
import StoreKit

/// TickLab Pro — 월간 / 연간 자동 갱신 구독. 가격은 App Store 표시값(지역별).
///
/// Free tier 제한:
/// - 시계 등록 최대 1개
/// - 측정 하루 3회
/// - 일기 월 5개
/// - AI Diagnosis trial 3회/시계
/// Pro: 모든 제한 해제 + Share Card 고급 스타일 + Service log 무제한.
/// 출시 프로모 — 이 시점 전까지 전원 Pro 전체 기능 무료(구독 불필요). 이후 정상 구독 게이트로 복귀.
/// 2026-06-05 출시 기준 약 3개월. 전역 고정 종료일(설치일 무관) — 날짜만 바꾸면 연장/종료.
enum LaunchPromo {
    static let proFreeUntil: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = 30
        c.hour = 23; c.minute = 59; c.second = 59
        return Calendar.current.date(from: c) ?? .distantPast
    }()
    /// 테스트/디버그 강제값 — nil 이면 날짜 기준. (엔타이틀먼트 단위테스트가 프로모를 끄고 realPro 검증)
    static var overrideActive: Bool?
    /// 프로모 진행 중 여부 — Pro 게이트(isPro)가 OR 로 참조.
    static var isActive: Bool { overrideActive ?? (Date() < proFreeUntil) }

    /// 앱 내장 프로모 공지 식별자(백엔드 불필요 — 하루 1회 dismiss 키로도 사용).
    static let announcementID = "ticklab.promo.launch.2026q3"
    /// 종료일 현지화 표기(예: 2026. 9. 30.).
    static var endDateText: String { proFreeUntil.formatted(date: .abbreviated, time: .omitted) }
}

@MainActor
final class ProEntitlement: ObservableObject {
    static let shared = ProEntitlement()

    static let monthlyProductId  = "com.ticklab.watchaccuracypro.pro.monthly"
    static let yearlyProductId   = "com.ticklab.app.pro.yearly"
    static let allProductIds: Set<String> = [monthlyProductId, yearlyProductId]
    static let freeWatchLimit = 1
    static let freeDailyMeasurementLimit = 3
    static let freeJournalMonthLimit = 5
    static let freeAITrialPerWatch = 3

    /// StoreKit 실제 구독 상태(검증된 entitlement). 게이트는 아래 computed `isPro` 사용.
    @Published private(set) var realPro: Bool = false
    /// 게이트가 참조하는 Pro 접근권 — 출시 프로모 기간엔 전원 true.
    var isPro: Bool { LaunchPromo.isActive || realPro }

    /// Round 15 (Jay): 중복 listener 방지. iPad multi-window scene rebuild 시
    ///   startTransactionListener 가 두 번 호출되면 double-finish 위험.
    private var listenerTask: Task<Void, Never>?

    private init() {
        // UserDefaults 에서 빠른 lookup (UserPreferences 와 sync).
        self.realPro = UserDefaults.standard.bool(forKey: "ticklab.isPro")
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
        if Self.allProductIds.contains(transaction.productID) {
            if transaction.revocationDate == nil {
                storeKitMarkPro(true)
            } else {
                storeKitMarkPro(false)
            }
        }
        await transaction.finish()
    }

    /// Purchase entry — PurchaseView 가 선택한 Product 를 넘김.
    func purchase(_ product: Product) async throws -> Bool {
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
        // Min 팀 보고 fix: 기존 코드는 entitlement 이터레이션 순서에 따라 활성 monthly 뒤
        //   환불된 lifetime 처리 시 isPro=false 로 끝나던 race. 모든 entitlement 를 한 번에 평가 후
        //   최종 결정. transaction.finish() 만 루프 안에서 호출.
        var foundActiveEntitlement = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if Self.allProductIds.contains(transaction.productID),
               transaction.revocationDate == nil {
                foundActiveEntitlement = true
            }
            await transaction.finish()
        }
        // 활성 entitlement 가 하나라도 있으면 true, 없으면 false — 최종 단일 set.
        storeKitMarkPro(foundActiveEntitlement)
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
        guard realPro != on else { return }
        realPro = on
        UserDefaults.standard.set(on, forKey: "ticklab.isPro")
        // Round 149 (Hyemi 7 H1): UserPreferences 인스턴스 갱신 — observer 들이 즉시 반응.
        NotificationCenter.default.post(name: .ticklabProEntitlementChanged, object: nil, userInfo: ["isPro": on])
    }
}
