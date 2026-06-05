import Foundation

/// 위젯과 메인 앱이 공유하는 가장 최근 측정 스냅샷.
/// App Group `group.com.ticklab.watchaccuracypro` 의 UserDefaults 에 JSON 으로 저장.
struct LatestMeasurementSnapshot: Codable, Equatable, Sendable {
    /// Round 17/24 (Doyoon/Min): app ↔ widget 프로세스 간 schema 변화 감지용.
    /// **호환 규칙 (반드시 준수)**:
    /// 1. 신규 필드는 **반드시 Optional + default** 로 추가 (양방향 decode 호환).
    /// 2. 기존 필드 type 변경 또는 제거 시 schemaVersion bump + 매뉴얼 마이그레이션.
    /// 3. read() 가 currentMaxKnown 초과 version 만나면 nil 반환 → widget placeholder.
    /// 4. 같은 schemaVersion 안에서 Optional 추가는 안전, required 추가는 호환성 깸.
    static let currentSchemaVersion: Int = 1
    var schemaVersion: Int = LatestMeasurementSnapshot.currentSchemaVersion
    var watchName: String
    var caliber: String?
    var timestamp: Date
    var rateSecondsPerDay: Double
    var beatErrorMs: Double
    var amplitudeDegrees: Double?
    var bph: Int
    var confidenceScore: Int

    // MARK: - Round 178 (위젯 확장): 한눈 정보용 추가 필드
    //   호환 규칙(상단 주석) 준수 — 모두 **Optional + default nil** → 같은 schemaVersion 안에서 안전.
    //   구버전 앱이 쓴 데이터에 이 필드들이 없어도 decode 성공(nil 로 채워짐), 신버전 위젯은 nil 을 graceful 처리.

    /// 시계 무브먼트 타입 raw (`automatic`/`manual`/`quartz`/`solar`/`smartwatch`).
    /// 위젯이 기계식↔배터리 표시를 분기하는 데 사용. nil = 미상(legacy) → 기계식으로 간주.
    var movementTypeRaw: String?
    /// 배터리 잔량 퍼센트(0~100) — 스마트워치/쿼츠 전용. nil = 데이터 없음/해당 없음.
    var batteryPercent: Int?
    /// 다음 오버홀(전체 정비) 예상일 — 기계식 전용. nil = 미설정.
    var nextOverhaulDate: Date?
    /// 신뢰도 라벨(`high`/`medium`/`low`) — Hard Rule #9: medium/low 캘리버는 amplitude 비노출.
    /// nil = 미상 → amplitude 표시 허용(legacy 동작 유지).
    var confidenceLabel: String?

    static let placeholder = LatestMeasurementSnapshot(
        watchName: "TickLab",
        caliber: nil,
        timestamp: Date(),
        rateSecondsPerDay: 0,
        beatErrorMs: 0,
        amplitudeDegrees: nil,
        bph: 28800,
        confidenceScore: 0
    )

    init(
        schemaVersion: Int = LatestMeasurementSnapshot.currentSchemaVersion,
        watchName: String,
        caliber: String? = nil,
        timestamp: Date,
        rateSecondsPerDay: Double,
        beatErrorMs: Double,
        amplitudeDegrees: Double? = nil,
        bph: Int,
        confidenceScore: Int,
        movementTypeRaw: String? = nil,
        batteryPercent: Int? = nil,
        nextOverhaulDate: Date? = nil,
        confidenceLabel: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.watchName = watchName
        self.caliber = caliber
        self.timestamp = timestamp
        self.rateSecondsPerDay = rateSecondsPerDay
        self.beatErrorMs = beatErrorMs
        self.amplitudeDegrees = amplitudeDegrees
        self.bph = bph
        self.confidenceScore = confidenceScore
        self.movementTypeRaw = movementTypeRaw
        self.batteryPercent = batteryPercent
        self.nextOverhaulDate = nextOverhaulDate
        self.confidenceLabel = confidenceLabel
    }

    /// 무브먼트가 배터리 구동(스마트워치/쿼츠/솔라)인지 — 위젯이 배터리 vs 오버홀 분기에 사용.
    var isBatteryPowered: Bool {
        switch movementTypeRaw {
        case "quartz", "solar", "smartwatch": return true
        default: return false   // automatic/manual/nil → 기계식
        }
    }
}

enum SharedSnapshotStore {
    static let appGroupId = "group.com.ticklab.watchaccuracypro"
    private static let key = "ticklab.latestSnapshot"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    /// Round 17 (Doyoon): JSONEncoder/Decoder 의 date strategy 를 명시 — 양쪽 프로세스가
    ///   같은 형식을 약속하지 않으면 widget decode 가 silently fail 한 채 stale placeholder 노출.
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func write(_ snapshot: LatestMeasurementSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }

    /// Round 178 (위젯 확장): 측정 결과 + 시계 컨텍스트(무브먼트/배터리/오버홀)를 한 번에 저장.
    /// 앱(MeasurementViewModel)에서 직접 struct 를 조립하는 대신 이 메서드로 호출하면
    /// 신규 필드 누락 없이 위젯에 풀 정보가 전달된다.
    ///
    /// **통합 담당 wire 지점**: 호출부는 `SharedSnapshotStore.write(snapshot)` 와 동일하므로
    /// 기존 호출을 이 시그니처로 교체하거나, struct 조립 시 새 필드를 채우면 된다(아래 보고 참조).
    static func writeMeasurement(
        watchName: String,
        caliber: String?,
        timestamp: Date,
        rateSecondsPerDay: Double,
        beatErrorMs: Double,
        amplitudeDegrees: Double?,
        bph: Int,
        confidenceScore: Int,
        movementTypeRaw: String?,
        batteryPercent: Int?,
        nextOverhaulDate: Date?,
        confidenceLabel: String?
    ) {
        write(LatestMeasurementSnapshot(
            watchName: watchName,
            caliber: caliber,
            timestamp: timestamp,
            rateSecondsPerDay: rateSecondsPerDay,
            beatErrorMs: beatErrorMs,
            amplitudeDegrees: amplitudeDegrees,
            bph: bph,
            confidenceScore: confidenceScore,
            movementTypeRaw: movementTypeRaw,
            batteryPercent: batteryPercent,
            nextOverhaulDate: nextOverhaulDate,
            confidenceLabel: confidenceLabel
        ))
    }

    /// 측정 없이 시계 컨텍스트(배터리/오버홀/무브먼트/이름)만 갱신하고 싶을 때 — 기존 측정 스냅샷에 머지.
    /// 예: 컬렉션에서 대표 시계를 바꾸거나, 스마트워치 배터리 % 가 시간 경과로 변할 때 위젯을 fresh 하게.
    /// 기존 스냅샷이 없으면 no-op(측정 한 번은 있어야 의미 있는 위젯).
    static func updateWatchContext(
        watchName: String? = nil,
        movementTypeRaw: String? = nil,
        batteryPercent: Int? = nil,
        nextOverhaulDate: Date? = nil
    ) {
        guard var snapshot = read() else { return }
        if let watchName { snapshot.watchName = watchName }
        if let movementTypeRaw { snapshot.movementTypeRaw = movementTypeRaw }
        snapshot.batteryPercent = batteryPercent
        snapshot.nextOverhaulDate = nextOverhaulDate
        write(snapshot)
    }

    static func read() -> LatestMeasurementSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        guard let decoded = try? decoder.decode(LatestMeasurementSnapshot.self, from: data) else { return nil }
        // Round 24 (Min): 미지 schema 버전 → widget 이 보장된 형식으로만 표시하도록 nil (placeholder fallback).
        //   alien version 데이터를 추정 표시하지 않음.
        guard decoded.schemaVersion <= LatestMeasurementSnapshot.currentSchemaVersion else { return nil }
        return decoded
    }

    static func clear() {
        defaults?.removeObject(forKey: key)
    }

    // MARK: - 위젯 착용 버튼 상태 (App Group 공유)

    /// 위젯에 표시되는 시계(=최근 측정)의 "오늘 착용" 상태. 앱이 권위값을 쓰고 위젯은 읽어 버튼 표시.
    static let wornTodayKey = "ticklab.latestWatchWornToday"
    /// 위젯 착용 버튼 탭 → 앱이 활성화 시 desired 상태로 reconcile 하도록 신호(큐).
    static let pendingWearToggleKey = "ticklab.pendingWearToggleAt"

    static func writeWornToday(_ worn: Bool) { defaults?.set(worn, forKey: wornTodayKey) }
    static func readWornToday() -> Bool { defaults?.bool(forKey: wornTodayKey) ?? false }
}
