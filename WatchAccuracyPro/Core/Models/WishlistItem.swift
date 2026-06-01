import Foundation
import SwiftData

/// Sprint 9 (P2-19): 드림 시계 위시리스트.
/// Chrono24 없이 수동 목표가 + 달성률 게이지.
@Model
final class WishlistItem {
    @Attribute(.unique) var id: UUID
    var brand: String
    var model: String
    var referenceNumber: String?
    var targetPrice: Decimal?
    var currency: String
    var note: String
    var imageData: Data?
    var createdAt: Date
    /// 팀 토론: 저축 진행 트래커 — 현재 모은 금액 + 월 적립 목표(rule 기반 코칭, 외부 시세 API 없음).
    /// lightweight migration — 기본값 있는 추가 속성.
    var savedAmount: Decimal = 0
    var monthlyGoal: Decimal? = nil

    init(
        id: UUID = UUID(),
        brand: String,
        model: String,
        referenceNumber: String? = nil,
        targetPrice: Decimal? = nil,
        currency: String = Locale.current.currency?.identifier ?? "KRW",
        note: String = "",
        imageData: Data? = nil,
        createdAt: Date = .init()
    ) {
        self.id = id; self.brand = brand; self.model = model
        self.referenceNumber = referenceNumber
        self.targetPrice = targetPrice; self.currency = currency
        self.note = note; self.imageData = imageData; self.createdAt = createdAt
    }

    /// 달성률 0~1 (목표가·저축액 있을 때). 없으면 nil.
    var savingsProgress: Double? {
        guard let target = targetPrice, target > 0 else { return nil }
        let p = NSDecimalNumber(decimal: savedAmount).doubleValue / NSDecimalNumber(decimal: target).doubleValue
        return min(1.0, max(0.0, p))
    }

    /// 월 적립 목표 기준 남은 개월 수(올림). 목표·월적립·잔액 있을 때.
    var monthsToGoal: Int? {
        guard let target = targetPrice, let monthly = monthlyGoal,
              monthly > 0, target > savedAmount else { return nil }
        let remaining = NSDecimalNumber(decimal: target - savedAmount).doubleValue
        let per = NSDecimalNumber(decimal: monthly).doubleValue
        return Int((remaining / per).rounded(.up))
    }
}

extension WishlistItem: Identifiable {}
