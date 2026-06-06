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
    /// #18 짝: 함께한 사람 / 이벤트 태그 — 추억을 검색 가능하게. WearTag JSON 패턴(lightweight migration).
    var peopleRaw: String = "[]"
    var eventRaw: String = "[]"

    var people: [String] {
        get { (try? JSONDecoder().decode([String].self, from: Data(peopleRaw.utf8))) ?? [] }
        set { peopleRaw = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
    }
    var events: [String] {
        get { (try? JSONDecoder().decode([String].self, from: Data(eventRaw.utf8))) ?? [] }
        set { eventRaw = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
    }

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

/// 무드 — 19종(긍정 8 · 사색 5 · 복잡 6). rawValue 는 영구 저장 키이므로 기존 6종
/// (happy/proud/curious/neutral/concerned/nostalgic)은 절대 변경 금지(기존 일기 호환).
enum Mood: String, CaseIterable, Codable, Sendable {
    // 긍정
    case happy          // 만족
    case excited        // 설렘
    case proud          // 자랑
    case awe            // 감탄
    case accomplished   // 뿌듯
    case love           // 애정
    case relief         // 안도
    case calm           // 평온
    // 사색·중립
    case neutral        // 평범
    case curious        // 호기심
    case focused        // 집중
    case thoughtful     // 사색
    case nostalgic      // 향수
    // 복잡·부정
    case concerned      // 우려
    case disappointed   // 실망
    case surprised      // 놀람
    case confused       // 혼란
    case longing        // 그리움
    case tired          // 지침

    enum Category: String, CaseIterable {
        case positive, reflective, complex
        var localizedName: String { NSLocalizedString("mood.category.\(rawValue)", comment: "") }
    }

    var category: Category {
        switch self {
        case .happy, .excited, .proud, .awe, .accomplished, .love, .relief, .calm: return .positive
        case .neutral, .curious, .focused, .thoughtful, .nostalgic: return .reflective
        case .concerned, .disappointed, .surprised, .confused, .longing, .tired: return .complex
        }
    }

    /// 폴백/내보내기용 이모지(화면 표시는 MoodIcon 벡터 사용).
    var emoji: String {
        switch self {
        case .happy: return "😊"; case .excited: return "🤩"; case .proud: return "✨"
        case .awe: return "😮"; case .accomplished: return "✅"; case .love: return "🥰"
        case .relief: return "😌"; case .calm: return "🧘"; case .neutral: return "😐"
        case .curious: return "🔍"; case .focused: return "🎯"; case .thoughtful: return "🤔"
        case .nostalgic: return "🕰️"; case .concerned: return "😟"; case .disappointed: return "😞"
        case .surprised: return "😲"; case .confused: return "😕"; case .longing: return "🥺"
        case .tired: return "😴"
        }
    }

    var localizedName: String {
        NSLocalizedString("mood.\(rawValue)", comment: "")
    }
}

extension JournalEntry: Identifiable {}
