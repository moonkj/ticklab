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
}
