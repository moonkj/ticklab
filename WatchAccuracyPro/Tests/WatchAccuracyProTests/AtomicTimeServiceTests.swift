import XCTest
@testable import WatchAccuracyPro

final class AtomicTimeServiceTests: XCTestCase {
    func test_request_packet_is_48_bytes_with_correct_header() {
        let packet = AtomicTimeService.makeRequestPacket()
        XCTAssertEqual(packet.count, 48)
        // LI=0 (00), VN=4 (100), Mode=3 (011) → 0b00100011 = 0x23
        XCTAssertEqual(packet[0], 0x23)
        // 나머지 0
        for i in 1..<48 {
            XCTAssertEqual(packet[i], 0, "byte \(i) 는 0 이어야 한다")
        }
    }

    func test_parse_sample_rejects_short_response() {
        let short = Data([0, 0, 0])
        XCTAssertThrowsError(try AtomicTimeService.parseSample(
            response: short, txTime: Date(), rxTime: Date()
        ))
    }

    func test_parse_sample_rejects_invalid_mode() {
        var bytes = [UInt8](repeating: 0, count: 48)
        bytes[0] = 0b00_100_011 // Mode=3 (client) — 서버 응답에선 4 여야 한다
        bytes[1] = 1
        let resp = Data(bytes)
        XCTAssertThrowsError(try AtomicTimeService.parseSample(
            response: resp, txTime: Date(), rxTime: Date()
        ))
    }

    func test_parse_sample_with_synthetic_zero_offset() throws {
        // 합성: 서버 receive/transmit 둘 다 (txTime + rxTime)/2 으로 설정 → offset 0 근처
        let txTime = Date(timeIntervalSince1970: 1_700_000_000)
        let rxTime = txTime.addingTimeInterval(0.020) // 20ms RTT

        var bytes = [UInt8](repeating: 0, count: 48)
        bytes[0] = 0b00_100_100 // LI=0, VN=4, Mode=4 (server)
        bytes[1] = 1            // stratum > 0 < 16

        let server = txTime.addingTimeInterval(0.010).timeIntervalSince1970
        let ntpEpoch: TimeInterval = 2_208_988_800
        let totalSecs = server + ntpEpoch
        let secs = UInt32(totalSecs)
        let frac = UInt32((totalSecs - TimeInterval(secs)) * TimeInterval(UInt64(1) << 32))
        for offset in [32, 40] {
            bytes[offset]     = UInt8((secs >> 24) & 0xFF)
            bytes[offset + 1] = UInt8((secs >> 16) & 0xFF)
            bytes[offset + 2] = UInt8((secs >> 8)  & 0xFF)
            bytes[offset + 3] = UInt8( secs        & 0xFF)
            bytes[offset + 4] = UInt8((frac >> 24) & 0xFF)
            bytes[offset + 5] = UInt8((frac >> 16) & 0xFF)
            bytes[offset + 6] = UInt8((frac >> 8)  & 0xFF)
            bytes[offset + 7] = UInt8( frac        & 0xFF)
        }
        let sample = try AtomicTimeService.parseSample(
            response: Data(bytes), txTime: txTime, rxTime: rxTime
        )
        // offset 부호 = -((t2-t1)+(t3-t4))/2 = -((10ms)+(-10ms))/2 = 0
        XCTAssertEqual(sample.offsetSeconds, 0, accuracy: 0.001)
        // delay = (t4-t1) - (t3-t2) = 20ms - 0 = 20ms
        XCTAssertEqual(sample.roundTripSeconds, 0.020, accuracy: 0.001)
    }
}
