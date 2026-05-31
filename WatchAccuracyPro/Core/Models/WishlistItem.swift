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
}

extension WishlistItem: Identifiable {}
