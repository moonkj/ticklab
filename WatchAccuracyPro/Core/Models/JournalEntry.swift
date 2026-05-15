import Foundation
import SwiftData

/// TickLab v3 Pivot: 시계와 함께하는 매일의 기록.
/// 측정 + 사진 + 코멘트 + 무드를 묶어 timeline 으로 시각화.
@Model
final class JournalEntry {
    @Attribute(.unique) var id: UUID
    var watch: Watch?
    /// 연결된 측정 — optional. 측정 없는 일반 일기도 허용.
    var measurementId: UUID?
    var timestamp: Date
    var body: String
    /// 첨부 사진 — file system path. EXIF strip 후 저장.
    var photoPaths: [String]
    /// Mood — pre-defined enum. 시계와의 감정 기록.
    var moodRaw: String
    /// 자동 또는 수동 location (city level only — privacy).
    var locationLabel: String?

    var mood: Mood {
        get { Mood(rawValue: moodRaw) ?? .neutral }
        set { moodRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        watch: Watch? = nil,
        measurementId: UUID? = nil,
        timestamp: Date = .init(),
        body: String = "",
        photoPaths: [String] = [],
        mood: Mood = .neutral,
        locationLabel: String? = nil
    ) {
        self.id = id
        self.watch = watch
        self.measurementId = measurementId
        self.timestamp = timestamp
        self.body = body
        self.photoPaths = photoPaths
        self.moodRaw = mood.rawValue
        self.locationLabel = locationLabel
    }
}

enum Mood: String, CaseIterable, Codable, Sendable {
    case happy        // 😊 만족
    case proud        // ✨ 자랑스러움
    case curious      // 🔍 호기심
    case neutral      // 😐 평범
    case concerned    // 😟 우려
    case nostalgic    // 🕰️ 향수

    var emoji: String {
        switch self {
        case .happy: return "😊"
        case .proud: return "✨"
        case .curious: return "🔍"
        case .neutral: return "😐"
        case .concerned: return "😟"
        case .nostalgic: return "🕰️"
        }
    }

    var localizedName: String {
        NSLocalizedString("mood.\(rawValue)", comment: "")
    }
}

extension JournalEntry: Identifiable {}
