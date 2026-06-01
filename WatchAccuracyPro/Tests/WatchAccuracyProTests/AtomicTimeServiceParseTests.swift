import XCTest
@testable import WatchAccuracyPro

/// `AtomicTimeService.parseSample` / `atomicNow` 순수 분기 추가 커버.
/// 기존 `AtomicTimeServiceTests` 가 다루지 않는 경계:
///   - stratum 0 (Kiss-of-Death) / stratum 16 (unsynchronized) 거부
///   - 0 timestamp 거부
///   - 비대칭(non-zero) offset 산술
///   - atomicNow offset 적용
/// 네트워크 미사용 — 합성 패킷만.
final class AtomicTimeServiceParseTests: XCTestCase {

    private let ntpEpoch: TimeInterval = 2_208_988_800

    /// SNTP server 응답 48바이트 합성. mode=4, 지정 stratum, t2/t3 timestamp.
    private func makePacket(stratum: UInt8, serverReceive: TimeInterval, serverTransmit: TimeInterval) -> Data {
        var bytes = [UInt8](repeating: 0, count: 48)
        bytes[0] = 0b00_100_100 // LI=0, VN=4, Mode=4 (server)
        bytes[1] = stratum
        encode(serverReceive, into: &bytes, at: 32)
        encode(serverTransmit, into: &bytes, at: 40)
        return Data(bytes)
    }

    /// Unix epoch seconds → NTP 64-bit fixed point, big-endian, into bytes at offset.
    private func encode(_ unixSeconds: TimeInterval, into bytes: inout [UInt8], at offset: Int) {
        let total = unixSeconds + ntpEpoch
        let secs = UInt32(total)
        let frac = UInt32((total - TimeInterval(secs)) * TimeInterval(UInt64(1) << 32))
        bytes[offset]     = UInt8((secs >> 24) & 0xFF)
        bytes[offset + 1] = UInt8((secs >> 16) & 0xFF)
        bytes[offset + 2] = UInt8((secs >> 8)  & 0xFF)
        bytes[offset + 3] = UInt8( secs        & 0xFF)
        bytes[offset + 4] = UInt8((frac >> 24) & 0xFF)
        bytes[offset + 5] = UInt8((frac >> 16) & 0xFF)
        bytes[offset + 6] = UInt8((frac >> 8)  & 0xFF)
        bytes[offset + 7] = UInt8( frac        & 0xFF)
    }

    // MARK: - stratum 거부

    func test_rejects_stratum_zero_kiss_of_death() {
        let tx = Date(timeIntervalSince1970: 1_700_000_000)
        let rx = tx.addingTimeInterval(0.020)
        let server = tx.addingTimeInterval(0.010).timeIntervalSince1970
        let packet = makePacket(stratum: 0, serverReceive: server, serverTransmit: server)
        XCTAssertThrowsError(try AtomicTimeService.parseSample(response: packet, txTime: tx, rxTime: rx))
    }

    func test_rejects_stratum_16_unsynchronized() {
        let tx = Date(timeIntervalSince1970: 1_700_000_000)
        let rx = tx.addingTimeInterval(0.020)
        let server = tx.addingTimeInterval(0.010).timeIntervalSince1970
        let packet = makePacket(stratum: 16, serverReceive: server, serverTransmit: server)
        XCTAssertThrowsError(try AtomicTimeService.parseSample(response: packet, txTime: tx, rxTime: rx))
    }

    // MARK: - 0 timestamp 거부

    func test_rejects_zero_timestamps() {
        // mode/stratum 은 valid 인데 t2/t3 가 NTP epoch 그대로(즉 unix 0 이전) → 거부.
        var bytes = [UInt8](repeating: 0, count: 48)
        bytes[0] = 0b00_100_100
        bytes[1] = 1
        // bytes[32..47] 전부 0 → readNTPTime = -ntpEpoch < 0.
        XCTAssertThrowsError(try AtomicTimeService.parseSample(
            response: Data(bytes),
            txTime: Date(timeIntervalSince1970: 1_700_000_000),
            rxTime: Date(timeIntervalSince1970: 1_700_000_000.02)
        ))
    }

    // MARK: - 비대칭 offset 산술

    func test_parses_positive_server_ahead_offset() throws {
        // 서버 시계가 디바이스보다 5초 앞섬, RTT 20ms, 서버 처리 즉시.
        let tx = Date(timeIntervalSince1970: 1_700_000_000)        // t1
        let rx = tx.addingTimeInterval(0.020)                       // t4
        let serverTime = tx.timeIntervalSince1970 + 5.010           // t2 = t3 (즉시 처리)
        let packet = makePacket(stratum: 2, serverReceive: serverTime, serverTransmit: serverTime)

        let sample = try AtomicTimeService.parseSample(response: packet, txTime: tx, rxTime: rx)

        // offset = ((t2-t1)+(t3-t4))/2 = ((5.010)+(5.010-0.020))/2 = (5.010+4.990)/2 = 5.000
        // offsetSeconds = -offset = -5.000 (디바이스가 서버보다 뒤쳐짐 → 음수)
        XCTAssertEqual(sample.offsetSeconds, -5.000, accuracy: 0.002)
        // delay = (t4-t1) - (t3-t2) = 0.020 - 0 = 0.020
        XCTAssertEqual(sample.roundTripSeconds, 0.020, accuracy: 0.002)
        XCTAssertEqual(sample.measuredAt, rx)
    }

    func test_parses_negative_device_ahead_offset() throws {
        // 디바이스 시계가 서버보다 3초 앞섬 → offsetSeconds 양수.
        let tx = Date(timeIntervalSince1970: 1_700_000_000)
        let rx = tx.addingTimeInterval(0.040)
        let serverTime = tx.timeIntervalSince1970 - 3.020 // 서버가 3s 뒤, 처리 즉시 (중간 시각 근사)
        let packet = makePacket(stratum: 3, serverReceive: serverTime, serverTransmit: serverTime)

        let sample = try AtomicTimeService.parseSample(response: packet, txTime: tx, rxTime: rx)

        // offset = ((-3.020)+(-3.020-0.040))/2 = (-3.020 + -3.060)/2 = -3.040
        // offsetSeconds = -(-3.040) = +3.040
        XCTAssertEqual(sample.offsetSeconds, 3.040, accuracy: 0.002)
        XCTAssertEqual(sample.roundTripSeconds, 0.040, accuracy: 0.002)
    }

    // MARK: - atomicNow

    func test_atomic_now_applies_offset() {
        // offsetSeconds = 디바이스-서버. atomicNow = now - offsetSeconds.
        let service = AtomicTimeService()
        let sample = AtomicTimeService.NTPSample(
            offsetSeconds: 10, roundTripSeconds: 0.02, measuredAt: Date()
        )
        let before = Date().addingTimeInterval(-10)
        let atomic = service.atomicNow(offset: sample)
        // atomicNow 는 디바이스가 10s 앞서면 10s 뒤로 보정 → now-10 근처.
        XCTAssertEqual(atomic.timeIntervalSince1970, before.timeIntervalSince1970, accuracy: 0.5)
    }

    func test_atomic_now_zero_offset_is_now() {
        let service = AtomicTimeService()
        let sample = AtomicTimeService.NTPSample(
            offsetSeconds: 0, roundTripSeconds: 0, measuredAt: Date()
        )
        let atomic = service.atomicNow(offset: sample)
        XCTAssertEqual(atomic.timeIntervalSince1970, Date().timeIntervalSince1970, accuracy: 0.5)
    }
}
