import Foundation

/// Round 174: 뱃지 이모지 ↔ id 카탈로그(단일 소스). author_badge 는 이모지로 저장되므로
/// 커뮤니티 피드에서 닉네임 옆 뱃지 '이름'을 조회하는 데 사용. 이모지는 뱃지마다 고유.
/// BadgesView.swift 의 b(id, emoji, …) 정의에서 자동 추출 — 추가 시 함께 갱신.
enum BadgeCatalog {
    static let emojiToID: [String: String] = [
        // 감사 수정: b1~b9 누락 시 해당 9개 뱃지 장착 시 닉네임 옆 이름칩이 공백 처리됐음.
        "🌊": "b1",
        "🏆": "b2",
        "🎯": "b3",
        "🌅": "b4",
        "⚙️": "b5",
        "🌕": "b6",
        "✈️": "b7",
        "💯": "b8",
        "🎨": "b9",
        "✅": "b10",
        "🌙": "b16",
        "🔟": "b17",
        "📓": "b11",
        "🏅": "b13",
        "⏱️": "b18",
        "🕰️": "b20",
        "🌟": "b14",
        "🎵": "b15",
        "🔩": "b21",
        "🎖️": "b22",
        "👑": "b19",
        "🔮": "b12",
        "🔧": "b23",
        "🌚": "b24",
        "📖": "b25",
        "⏳": "b26",
        "🔄": "b27",
        "🎭": "b28",
        "💪": "b29",
        "🔬": "b30",
        "🍂": "b31",
        "🏛️": "b32",
        "🖼️": "b33",
        "👍": "b34",
        "🔥": "b35",
        "📷": "b36",
        "🤝": "b37",
        "📣": "b38",
    ]

    /// author_badge(이모지) → 현지화된 뱃지 이름. 미매칭(legacy/미등록)이면 nil.
    static func name(forBadge badge: String) -> String? {
        guard let id = emojiToID[badge] else { return nil }
        return NSLocalizedString("badges.\(id).name", comment: "")
    }
}
