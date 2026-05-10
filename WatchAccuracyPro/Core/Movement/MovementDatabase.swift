import Foundation

enum MovementDatabaseError: Error {
    case resourceMissing
    case decodeFailed(underlying: Error)
}

/// 무브먼트 정적 DB. 앱 번들 내 `MovementDB.json` 을 한 번만 로드해 캐싱한다.
/// Phase 2부터는 OTA 업데이트 가능하도록 확장 예정.
final class MovementDatabase {
    static let shared = MovementDatabase()

    private(set) var movements: [Movement]
    private let byID: [String: Movement]

    init(movements: [Movement]) {
        self.movements = movements
        self.byID = Dictionary(uniqueKeysWithValues: movements.map { ($0.id, $0) })
    }

    private convenience init() {
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

    func movement(id: String) -> Movement? { byID[id] }

    func liftAngle(forCaliber caliber: String?) -> Double? {
        guard let caliber else { return nil }
        return byID[caliber]?.liftAngleDegrees
    }
}
