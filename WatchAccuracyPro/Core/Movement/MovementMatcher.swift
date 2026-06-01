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

    // suggest() 는 자동감지용 — 기존 스코어링 유지(테스트 고정). 사용자 검색 퍼지는 MovementSearch 사용.
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

/// 4-1 (검색우선·퍼지): 무브먼트 picker 검색용 퍼지 매칭.
/// - 구분자(공백·언더스코어·하이픈) 무시 + 대소문자 무시 → "rolex 3135" = "Rolex_3135".
/// - 캘리버 id 오타 1~2자 허용(편집거리, 슬라이딩 윈도우).
/// pure function — 테스트 동반(MovementMatcherTests).
enum MovementSearch {
    /// 정규화: 소문자 + 영숫자만 (공백·언더스코어·하이픈 제거).
    static func normalize(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// Levenshtein 편집거리 (O(n·m), 메모리 O(m)).
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = Swift.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    /// 퍼지 점수 — nil = 매칭 안 됨, 높을수록 더 적합(정렬용).
    static func score(query: String, id: String, brandFamilies: [String]) -> Int? {
        let q = normalize(query)
        guard !q.isEmpty else { return 0 }
        let nid = normalize(id)
        // 1) 정규화 substring(구분자 무시)
        if nid.hasPrefix(q) { return 100 }
        if nid.contains(q) { return 90 }
        for b in brandFamilies where normalize(b).contains(q) { return 80 }
        // 2) 캘리버 id 오타 허용 — 슬라이딩 윈도우 최소 편집거리
        if q.count >= 3, nid.count >= q.count {
            let tol = q.count <= 5 ? 1 : 2
            let chars = Array(nid)
            for start in 0...(chars.count - q.count) {
                let d = editDistance(q, String(chars[start ..< start + q.count]))
                if d <= tol { return 60 - d }
            }
        }
        return nil
    }
}
