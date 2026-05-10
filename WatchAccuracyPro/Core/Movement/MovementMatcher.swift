import Foundation

/// 사용자 입력(브랜드/모델)을 무브먼트 DB의 캘리버에 매칭한다.
/// Phase 1에서는 단순 키워드 매칭만 지원 — 모호한 경우 nil을 돌려주고 사용자가 직접 선택하도록 한다.
struct MovementMatcher {
    let database: MovementDatabase

    init(database: MovementDatabase = .shared) {
        self.database = database
    }

    struct Suggestion: Equatable {
        let movement: Movement
        let score: Int
    }

    func suggest(brand: String, model: String) -> Suggestion? {
        let needle = "\(brand) \(model)".lowercased()
        guard !needle.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        var best: Suggestion?
        for movement in database.movements {
            var score = 0
            for family in movement.brandFamilies {
                let token = family.lowercased()
                if needle.contains(token) {
                    score += token.count
                } else {
                    let words = token.split(separator: " ").map(String.init)
                    for word in words where word.count >= 4 && needle.contains(word) {
                        score += word.count
                    }
                }
            }
            if score > 0 {
                if let current = best {
                    if score > current.score {
                        best = Suggestion(movement: movement, score: score)
                    }
                } else {
                    best = Suggestion(movement: movement, score: score)
                }
            }
        }
        return best
    }
}
