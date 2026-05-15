import Foundation
import SwiftData

/// 시계 오버홀/수리/점검 기록. WatchDetail 의 Service 탭에서 관리.
/// Pivot Addendum: "측정" 외 "Maintain" 축 — 다음 오버홀 reminder 자동 계산.
@Model
final class ServiceLog {
    @Attribute(.unique) var id: UUID
    var watch: Watch?
    var timestamp: Date
    var typeRaw: String
    var serviceCenter: String
    var costAmount: Decimal?
    var costCurrency: String?
    var notes: String
    /// 다음 service 권장 일자 (예: 5년 후). 자동 계산.
    var nextServiceDate: Date?
    /// 첨부 영수증 사진 path. EXIF strip 후.
    var receiptPath: String?

    var type: ServiceType {
        get { ServiceType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        watch: Watch? = nil,
        timestamp: Date = .init(),
        type: ServiceType = .checkup,
        serviceCenter: String = "",
        costAmount: Decimal? = nil,
        costCurrency: String? = nil,
        notes: String = "",
        nextServiceDate: Date? = nil,
        receiptPath: String? = nil
    ) {
        self.id = id
        self.watch = watch
        self.timestamp = timestamp
        self.typeRaw = type.rawValue
        self.serviceCenter = serviceCenter
        self.costAmount = costAmount
        self.costCurrency = costCurrency
        self.notes = notes
        self.nextServiceDate = nextServiceDate
        self.receiptPath = receiptPath
    }
}

enum ServiceType: String, CaseIterable, Codable, Sendable {
    case fullOverhaul       // 전체 오버홀 (5-7년 주기)
    case partialService     // 부분 점검
    case checkup            // 정확도 점검
    case waterTest          // 방수 테스트
    case batteryReplace     // 배터리 교체 (quartz, 기계식엔 무관)
    case crystalReplace     // 크리스털 교체
    case crownGasket        // 크라운/개스킷
    case bracelet           // 브레이슬릿
    case other

    var localizedName: String {
        NSLocalizedString("service.type.\(rawValue)", comment: "")
    }

    var recommendedIntervalMonths: Int? {
        switch self {
        case .fullOverhaul:  return 60        // 5년
        case .partialService: return 36       // 3년
        case .checkup:       return 12        // 1년
        case .waterTest:     return 24
        case .batteryReplace: return 24
        default:             return nil
        }
    }
}

extension ServiceLog: Identifiable {}
