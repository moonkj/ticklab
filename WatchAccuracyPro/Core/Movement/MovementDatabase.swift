import Foundation

enum MovementDatabaseError: Error {
    case resourceMissing
    case decodeFailed(underlying: Error)
}

/// 무브먼트 정적 DB. 앱 번들 내 `MovementDB.json` 을 한 번만 로드해 캐싱한다.
/// Phase 2 부터 OTA 업데이트 시 `replaceAll(with:)` 으로 in-place 교체 가능.
/// Round 5 (Min): OTA 적용과 측정 중 lookup 의 race 를 NSLock 으로 보호.
final class MovementDatabase {
    static let shared = MovementDatabase()

    private let lock = NSLock()
    private var _movements: [Movement]
    private var byID: [String: Movement]

    var movements: [Movement] {
        lock.lock(); defer { lock.unlock() }
        return _movements
    }

    init(movements: [Movement]) {
        self._movements = movements
        // Round 17 (Min): uniqueKeysWithValues 는 중복 id 만나면 trap → bad MovementDB.json 으로 앱 크래시.
        //   defensive grouping + first-wins + 디버그 빌드에서만 assert.
        var dict: [String: Movement] = [:]
        for m in movements {
            if dict[m.id] != nil {
                #if DEBUG
                assertionFailure("⚠️ MovementDB 에 중복 movement id 발견: \(m.id) — first-wins 로 진행.")
                #endif
                continue
            }
            dict[m.id] = m
        }
        self.byID = dict
    }

    private convenience init() {
        // 1) OTA 캐시 우선
        if let cached = MovementDBOTAService.shared.cachedMovements(), !cached.isEmpty {
            self.init(movements: cached)
            return
        }
        // 2) 번들 fallback
        do {
            let loaded = try Self.loadFromBundle(.main)
            self.init(movements: loaded)
        } catch {
            assertionFailure("MovementDB.json 로드 실패: \(error)")
            self.init(movements: [])
        }
    }

    static func loadFromBundle(_ bundle: Bundle) throws -> [Movement] {
        guard let url = bundle.url(forResource: "MovementDB", withExtension: "json") else {
            throw MovementDatabaseError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode([Movement].self, from: data)
        } catch {
            throw MovementDatabaseError.decodeFailed(underlying: error)
        }
    }

    func movement(id: String) -> Movement? {
        lock.lock(); defer { lock.unlock() }
        return byID[id]
    }

    func liftAngle(forCaliber caliber: String?) -> Double? {
        guard let caliber else { return nil }
        lock.lock(); defer { lock.unlock() }
        return byID[caliber]?.liftAngleDegrees
    }

    /// OTA 적용 또는 테스트에서 in-place 교체. lookup 과 atomically.
    /// Round 8 (Min): dictionary 재구축은 lock 밖에서 수행하고 lock 안에선 swap 만.
    /// 큰 DB 에서도 lookup stall 시간 최소화.
    func replaceAll(with newMovements: [Movement]) {
        let newByID = Dictionary(uniqueKeysWithValues: newMovements.map { ($0.id, $0) })
        lock.lock(); defer { lock.unlock() }
        self._movements = newMovements
        self.byID = newByID
    }

    // MARK: - Brand search (T-07: AddWatchView 브랜드 자동완성)

    /// 알려진 브랜드 표시명. `brandFamilies` 엔트리("Rolex Submariner (vintage)" 등)에서
    /// 선두 브랜드를 식별하기 위한 사전. 멀티워드 브랜드("Grand Seiko", "TAG Heuer")는
    /// 단일 토큰 브랜드("Seiko")보다 먼저 매칭되도록 긴 것부터 시도한다.
    /// 데이터 전용(현지화 대상 아님) — `brandFamilies` 에 등장하는 실제 브랜드를 포괄.
    static let knownBrands: [String] = [
        "A. Lange & Söhne", "Audemars Piguet", "Bell & Ross", "Blancpain", "Breguet",
        "Breitling", "Bulova", "Cartier", "Christopher Ward", "Citizen", "F.P. Journe",
        "Frederique Constant", "Girard-Perregaux", "Glashütte Original", "Grand Seiko",
        "Hamilton", "Hublot", "IWC", "Jaeger-LeCoultre", "Longines", "Maurice Lacroix",
        "Mido", "Miyota", "Montblanc", "Nomos", "Omega", "Oris", "Panerai",
        "Patek Philippe", "Piaget", "Rolex", "Sellita", "Seiko", "Sinn", "TAG Heuer",
        "Tissot", "Tudor", "Ulysse Nardin", "Vacheron Constantin", "Zenith", "ETA"
    ]

    /// `brandFamilies` 엔트리에서 브랜드 표시명만 추출한다.
    /// ① `knownBrands` 중 prefix 로 일치하는 가장 긴 항목을 표준 브랜드로 채택
    ///   (예: "Rolex Submariner (vintage)" → "Rolex", "Grand Seiko Sport" → "Grand Seiko").
    /// ② 일치하는 known brand 가 없으면 괄호 한정자만 제거한 원문을 후보로 둔다
    ///   (단 "microbrand" 같은 일반 분류 토큰은 제외).
    static func normalizedBrandName(_ raw: String) -> String? {
        var name = raw
        if let parenIndex = name.firstIndex(of: "(") {
            name = String(name[name.startIndex..<parenIndex])
        }
        name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let lower = name.lowercased()
        // 긴 브랜드명부터 매칭 (멀티워드 우선).
        for brand in knownBrands.sorted(by: { $0.count > $1.count }) {
            let b = brand.lowercased()
            if lower == b || lower.hasPrefix(b + " ") {
                return brand
            }
        }
        // 자동완성에 의미 없는 일반 분류 토큰 제외.
        let generic: Set<String> = ["microbrand", "various", "generic"]
        if generic.contains(lower) { return nil }
        return name
    }

    /// DB 의 모든 brandFamilies 에서 정규화·중복 제거한 브랜드 표시명 목록 (알파벳 순).
    func brandNames() -> [String] {
        let all = movements  // lock 보호된 snapshot.
        var seen = Set<String>()      // 소문자 기준 중복 제거.
        var result: [String] = []
        for movement in all {
            for family in movement.brandFamilies {
                guard let name = Self.normalizedBrandName(family) else { continue }
                let key = name.lowercased()
                if seen.insert(key).inserted {
                    result.append(name)
                }
            }
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// brand 자동완성 검색.
    /// 정렬: ① 대소문자 무시 정확 일치 ② prefix 일치 ③ contains 일치. 중복 제거 후 `limit` 개로 cap.
    /// 빈/공백 query → 빈 배열.
    func searchBrands(_ query: String, limit: Int = 6) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let brands = brandNames()
        var exact: [String] = []
        var prefix: [String] = []
        var contains: [String] = []
        for brand in brands {
            let lower = brand.lowercased()
            if lower == q {
                exact.append(brand)
            } else if lower.hasPrefix(q) {
                prefix.append(brand)
            } else if lower.contains(q) {
                contains.append(brand)
            }
        }
        let ordered = exact + prefix + contains
        return Array(ordered.prefix(limit))
    }

    /// `shared` 인스턴스 기준 정적 진입점 — view 에서 간편 호출용.
    static func searchBrands(_ query: String, limit: Int = 6) -> [String] {
        shared.searchBrands(query, limit: limit)
    }
}
