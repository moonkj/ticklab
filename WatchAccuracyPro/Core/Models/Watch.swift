import Foundation
import SwiftData

@Model
final class Watch {
    @Attribute(.unique) var id: UUID
    var brand: String
    var model: String
    var caliber: String?
    var purchaseDate: Date?
    var photoData: Data?
    var serviceHistory: [Date]
    /// SwiftData iOS 17 버그 회피: `inverse:` 를 명시하면 명시적 `save()` 후 cascade 가 발동되지 않는다.
    /// 인버스는 SwiftData가 `WatchMeasurement.watch` 로부터 자동 추론하도록 두고, 기본값은 선언부에서 부여한다.
    @Relationship(deleteRule: .cascade)
    var measurements: [WatchMeasurement] = []
    var createdAt: Date

    init(
        id: UUID = UUID(),
        brand: String,
        model: String,
        caliber: String? = nil,
        purchaseDate: Date? = nil,
        photoData: Data? = nil,
        serviceHistory: [Date] = [],
        createdAt: Date = .init()
    ) {
        self.id = id
        self.brand = brand
        self.model = model
        self.caliber = caliber
        self.purchaseDate = purchaseDate
        self.photoData = photoData
        self.serviceHistory = serviceHistory
        self.createdAt = createdAt
    }
}
