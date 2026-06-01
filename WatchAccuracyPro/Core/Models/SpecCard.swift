import Foundation
import SwiftData

/// 시계 스펙 카드 — 사진/제품명/무브먼트/사이즈/사운드 녹음 묶음.
/// 사용자가 자신의 시계를 "공식 카탈로그" 처럼 보여줄 수 있는 collectible card.
/// 무브먼트 사운드 녹음 (5초) 을 첨부해 "tic 사운드까지 보관".
@Model
final class SpecCard {
    @Attribute(.unique) var id: UUID
    var watch: Watch?
    var createdAt: Date
    /// 카드 표시 제목 — 기본은 watch.brand + model.
    var title: String
    /// 무브먼트 무브 번호 (예: "ETA 7750"). 사용자 입력.
    var movement: String
    /// 케이스 사이즈 (mm). 사용자 입력.
    var caseSize: Double?
    /// 무브먼트 lift angle (°).
    var liftAngle: Double?
    /// Power reserve (hours).
    var powerReserveHours: Double?
    /// 사진 file system path (EXIF strip).
    var photoPath: String?
    /// 5초 무브먼트 소리 녹음 file path (m4a / aac).
    var audioPath: String?
    /// 부가 코멘트.
    var note: String
    /// AI 생성 모델 설명 + 착장 의견 캐시 — (현재 미사용, 추후 정리). lightweight migration.
    var aiDescription: String? = nil
    /// 팀 기획 2단계: 사용자 입력 스펙(DB·Watch가 모르는 것). 전부 optional·기본 nil — lightweight migration.
    var caseThickness: Double? = nil      // mm
    var lugToLug: Double? = nil           // mm
    var waterResistanceM: Int? = nil      // m
    var crystal: String? = nil            // 사파이어/미네랄/아크릴 등
    var dialColor: String? = nil
    var caseMaterial: String? = nil       // 스틸/티타늄/골드 등

    init(
        id: UUID = UUID(),
        watch: Watch? = nil,
        createdAt: Date = .init(),
        title: String = "",
        movement: String = "",
        caseSize: Double? = nil,
        liftAngle: Double? = nil,
        powerReserveHours: Double? = nil,
        photoPath: String? = nil,
        audioPath: String? = nil,
        note: String = ""
    ) {
        self.id = id
        self.watch = watch
        self.createdAt = createdAt
        self.title = title
        self.movement = movement
        self.caseSize = caseSize
        self.liftAngle = liftAngle
        self.powerReserveHours = powerReserveHours
        self.photoPath = photoPath
        self.audioPath = audioPath
        self.note = note
    }
}

extension SpecCard: Identifiable {}
