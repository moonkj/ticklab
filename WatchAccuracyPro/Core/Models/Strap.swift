import Foundation
import SwiftData

/// Sprint 5 (P3-1): 스트랩/브레이슬릿 데이터 모델.
/// 시계 하위 컴포넌트 — Watch.straps 관계.
@Model
final class Strap {
    @Attribute(.unique) var id: UUID
    var watch: Watch?
    var name: String
    var material: String
    var colorName: String
    /// 구매일.
    var purchaseDate: Date?
    /// 구매처 / 브랜드.
    var source: String?
    /// 대략적인 착용 횟수 (WearLog 연동 시 자동화 가능, 현재는 수동).
    var wearCount: Int = 0
    /// 교체 권장 착용 횟수 (예: 가죽 200회, 러버 500회). nil = 무제한.
    var replaceThreshold: Int?
    /// 사진 데이터 (EXIF strip 후).
    var photoData: Data?
    /// 메모.
    var note: String = ""
    var createdAt: Date

    init(
        id: UUID = UUID(),
        watch: Watch? = nil,
        name: String = "",
        material: String = "",
        colorName: String = "",
        purchaseDate: Date? = nil,
        source: String? = nil,
        wearCount: Int = 0,
        replaceThreshold: Int? = nil,
        photoData: Data? = nil,
        note: String = "",
        createdAt: Date = .init()
    ) {
        self.id = id
        self.watch = watch
        self.name = name
        self.material = material
        self.colorName = colorName
        self.purchaseDate = purchaseDate
        self.source = source
        self.wearCount = wearCount
        self.replaceThreshold = replaceThreshold
        self.photoData = photoData
        self.note = note
        self.createdAt = createdAt
    }

    var isNearReplacement: Bool {
        guard let threshold = replaceThreshold else { return false }
        return wearCount >= Int(Double(threshold) * 0.8)
    }
}

extension Strap: Identifiable {}
