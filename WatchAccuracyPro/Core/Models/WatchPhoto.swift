import Foundation
import SwiftData

/// Sprint 7 (P2-4): 역할별 시계 사진 — 대표/케이스백/스트랩/착용.
/// Watch.photoData (단일 사진) 외에 추가 사진을 역할별로 관리.
@Model
final class WatchPhoto {
    @Attribute(.unique) var id: UUID
    var watch: Watch?
    var roleRaw: String
    var photoData: Data
    var note: String = ""
    var createdAt: Date

    var role: PhotoRole {
        get { PhotoRole(rawValue: roleRaw) ?? .other }
        set { roleRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        watch: Watch? = nil,
        role: PhotoRole = .other,
        photoData: Data,
        note: String = "",
        createdAt: Date = .init()
    ) {
        self.id = id
        self.watch = watch
        self.roleRaw = role.rawValue
        self.photoData = photoData
        self.note = note
        self.createdAt = createdAt
    }
}

enum PhotoRole: String, CaseIterable, Identifiable, Sendable {
    case hero        // 대표 사진
    case caseback    // 케이스백
    case strap       // 스트랩/브레이슬릿
    case wrist       // 착용 사진
    case other       // 기타

    var id: String { rawValue }

    var localizedName: LocalizedStringResource {
        switch self {
        case .hero:     return "photo.role.hero"
        case .caseback: return "photo.role.caseback"
        case .strap:    return "photo.role.strap"
        case .wrist:    return "photo.role.wrist"
        case .other:    return "photo.role.other"
        }
    }

    var icon: String {
        switch self {
        case .hero:     return "star.fill"
        case .caseback: return "gear"
        case .strap:    return "watch.analog"
        case .wrist:    return "hand.raised"
        case .other:    return "photo"
        }
    }
}

extension WatchPhoto: Identifiable {}
