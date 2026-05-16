import Foundation
import SwiftData

enum WatchMovementType: String, CaseIterable, Codable, Sendable {
    case automatic
    case manual
    case quartz

    var displayName: String {
        switch self {
        case .automatic: return String(localized: "movementtype.automatic")
        case .manual:    return String(localized: "movementtype.manual")
        case .quartz:    return String(localized: "movementtype.quartz")
        }
    }
}

@Model
final class Watch {
    @Attribute(.unique) var id: UUID
    var brand: String
    var model: String
    var caliber: String?
    var purchaseDate: Date?
    // Round 140 (Hyemi/Min Critical): Round 139 의 @Attribute(.externalStorage) revert.
    // SwiftData lightweight migration 이 attribute option 변경을 처리 안 함 → 기존 사용자 store 손실 위험.
    // 대안: 100개 이상 등록 케이스에 진입 시 별도 schema migration plan 으로 처리 (Phase 2).
    var photoData: Data?
    var serviceHistory: [Date]
    /// 즐겨찾기 — 페르소나 (이재현/박지영) 피드백: UI 떡밥만 있고 동작 X 였던 버그 수정.
    var isFavorite: Bool
    /// 대표 시계 — Collection Hero 슬롯에 표시될 시계. 컬렉션 내 1개만 true.
    var isPrimary: Bool = false
    /// Round 170: 사용자 정의 정렬 순서 (drag-to-reorder). 낮을수록 위에 표시.
    /// 기본 nil → createdAt 기준 정렬 (legacy). 사용자가 reorder 하면 부여됨.
    var sortOrder: Double? = nil
    /// Round 83 (정수민): 별명 / "할아버지의 첫 월급" 같은 personalisation 필드. SwiftData lightweight migration.
    var nickname: String? = nil
    /// Round 83 (정수민): 시계의 이야기 — 누구한테 받았는지, 구입 사연. 자유 텍스트.
    var story: String? = nil
    /// Round 83 (이재현): reference number — 시리얼이 아닌 모델 ref no.
    var referenceNumber: String? = nil
    /// 페르소나 (김재철, 워치메이커) wish: movement DB lookup 의 lift angle 을 watch 단위로 override.
    /// nil 이면 movement DB 의 default 사용. 워치메이커가 직접 측정한 값이 있을 때만 사용.
    var liftAngleOverride: Double?
    /// 무브먼트 직접입력 시 BPH. caliber == Watch.manualCaliberTag 일 때 사용.
    /// lightweight migration — optional + default nil. 측정 시 movement DB 보다 우선 적용.
    var customBph: Int? = nil

    /// Round 2-3 (Doyoon): sentinel 정의를 model layer 로 이동 — 다른 caller 가 magic string
    ///   "__manual__" 을 직접 type 하는 것을 막고 single source-of-truth 보장.
    ///   caliber == Watch.manualCaliberTag → 사용자가 customBph 로 직접입력한 무브먼트.
    static let manualCaliberTag = "__manual__"

    /// caliber 가 manual sentinel 인지 검증 — view 코드가 직접 비교 대신 이 helper 사용.
    var isCaliberManualEntry: Bool { caliber == Watch.manualCaliberTag }
    /// 무브먼트 타입 — "automatic" / "manual" / "quartz". 기본 automatic.
    /// String 저장 — SwiftData enum 마이그레이션 risk 회피.
    var movementTypeRaw: String = "automatic"
    /// 수동감기 리마인더 활성화. movementType == .manual 일 때만 의미 있음.
    var windReminderEnabled: Bool = false
    /// 매일 리마인더 시각 — 0..<24.
    var windReminderHour: Int = 9
    /// 매일 리마인더 분 — 0..<60.
    var windReminderMinute: Int = 0
    /// 마지막 배터리 교체일 — quartz 시계 전용.
    var batteryLastReplaced: Date?
    /// 배터리 예상 수명 (월 단위). 기본 30개월 (2.5년).
    var batteryExpectedLifeMonths: Int = 30
    /// 배터리 교체 알림 활성화 — quartz 전용.
    var batteryReminderEnabled: Bool = false
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
        isFavorite: Bool = false,
        isPrimary: Bool = false,
        liftAngleOverride: Double? = nil,
        movementType: WatchMovementType = .automatic,
        nickname: String? = nil,
        story: String? = nil,
        referenceNumber: String? = nil,
        // Round 19 (Min): 기존엔 default 만 의존하고 init 노출 X → 호출자가 후속 mutate 해야 했음.
        //   inconsistent — 모든 stored property 를 init 으로 set 가능하도록 추가.
        sortOrder: Double? = nil,
        customBph: Int? = nil,
        windReminderEnabled: Bool = false,
        windReminderHour: Int = 9,
        windReminderMinute: Int = 0,
        batteryLastReplaced: Date? = nil,
        batteryExpectedLifeMonths: Int = 30,
        batteryReminderEnabled: Bool = false,
        createdAt: Date = .init()
    ) {
        self.id = id
        self.brand = brand
        self.model = model
        self.caliber = caliber
        self.purchaseDate = purchaseDate
        self.photoData = photoData
        self.serviceHistory = serviceHistory
        self.isFavorite = isFavorite
        self.isPrimary = isPrimary
        self.liftAngleOverride = liftAngleOverride
        self.movementTypeRaw = movementType.rawValue
        self.nickname = nickname
        self.story = story
        self.referenceNumber = referenceNumber
        self.sortOrder = sortOrder
        self.customBph = customBph
        self.windReminderEnabled = windReminderEnabled
        self.windReminderHour = windReminderHour
        self.windReminderMinute = windReminderMinute
        self.batteryLastReplaced = batteryLastReplaced
        self.batteryExpectedLifeMonths = batteryExpectedLifeMonths
        self.batteryReminderEnabled = batteryReminderEnabled
        self.createdAt = createdAt
    }

    var movementType: WatchMovementType {
        get { WatchMovementType(rawValue: movementTypeRaw) ?? .automatic }
        set { movementTypeRaw = newValue.rawValue }
    }

    /// 다음 배터리 교체 예상일 — batteryLastReplaced 가 nil 이면 nil.
    var batteryNextDue: Date? {
        guard let last = batteryLastReplaced else { return nil }
        return Calendar.current.date(byAdding: .month, value: batteryExpectedLifeMonths, to: last)
    }
}
