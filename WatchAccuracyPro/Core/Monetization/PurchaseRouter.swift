import SwiftUI

/// 4개 분산된 .sheet(showingPurchase) 호스트를 1곳으로 통합.
/// 사용자 보고 fix: iPad multi-window 에서 동시에 여러 한도 도달 시 sheet 충돌 위험 + 코드 중복.
/// 진입점이 추가될 때마다 paywall 플러밍을 새로 안 깔아도 되도록 환경값으로 노출.
@MainActor
@Observable
final class PurchaseRouter {
    enum Intent: String {
        case watchLimit
        case dailyMeasurement
        case journalMonthly
        case aiTrial
        case settings

        /// 사용자 보고 fix: 어떤 한도가 트리거했는지 PurchaseView heading 으로 context 노출.
        var contextKey: String? {
            switch self {
            case .watchLimit:       return "purchase.context.watch_limit"
            case .dailyMeasurement: return "purchase.context.daily_measurement"
            case .journalMonthly:   return "purchase.context.journal_monthly"
            case .aiTrial:          return "purchase.context.ai_trial"
            case .settings:         return nil  // generic — no context banner
            }
        }
    }

    /// 마지막 의도 — PurchaseView 가 context banner 에 사용.
    private(set) var lastIntent: Intent?
    var isPresenting: Bool = false

    func intend(_ intent: Intent) {
        lastIntent = intent
        isPresenting = true
    }
}

private struct PurchaseRouterKey: EnvironmentKey {
    @MainActor static let defaultValue: PurchaseRouter? = nil
}

extension EnvironmentValues {
    var purchaseRouter: PurchaseRouter? {
        get { self[PurchaseRouterKey.self] }
        set { self[PurchaseRouterKey.self] = newValue }
    }
}
