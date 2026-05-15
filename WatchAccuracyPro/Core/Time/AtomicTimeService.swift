import Foundation
import Network

/// NTP 서버에서 atomic time offset 을 가져온다.
/// Phase 2 의 첫 외부 호출. 측정 duration 보정 용도로 사용 (실제 secondsPerDay 정확도 검증).
///
/// 프로토콜: SNTPv4 over UDP. 패킷 48 byte. transmit timestamp / receive timestamp 로 offset·delay 계산.
/// 기본 서버 후보: time.apple.com (Apple)·pool.ntp.org (백업).
final class AtomicTimeService {
    struct NTPSample: Equatable, Sendable {
        /// 디바이스 시계 - 서버 시계 (음수면 디바이스가 앞서감, 양수면 뒤쳐짐)
        let offsetSeconds: Double
        /// 왕복 지연
        let roundTripSeconds: Double
        /// 샘플 채취 시각 (디바이스 시계 기준)
        let measuredAt: Date
    }

    enum NTPError: Error, Equatable {
        case timeout
        case invalidResponse
        case networkUnavailable
    }

    static let shared = AtomicTimeService()

    private let servers: [String]
    private let timeoutSeconds: TimeInterval

    init(servers: [String] = ["time.apple.com", "pool.ntp.org"], timeoutSeconds: TimeInterval = 3.0) {
        self.servers = servers
        self.timeoutSeconds = timeoutSeconds
    }

    /// 등록된 모든 서버에 병렬로 요청해 첫 성공 응답을 채택한다.
    /// Round 4 (Jay, audit): 단일 loop 로 통일 — group.next() 가 한 곳에서만 호출되도록 정리.
    /// 모든 task 실패 시 마지막 오류 throw.
    func fetchSample() async throws -> NTPSample {
        guard !servers.isEmpty else { throw NTPError.networkUnavailable }
        return try await withThrowingTaskGroup(of: NTPSample.self) { group in
            for host in servers {
                group.addTask { try await self.query(host: host) }
            }
            var lastError: Error = NTPError.networkUnavailable
            // 모든 자식이 끝날 때까지 (또는 첫 성공할 때까지) 순회.
            while !group.isEmpty {
                do {
                    if let sample = try await group.next() {
                        group.cancelAll()
                        return sample
                    }
                } catch {
                    lastError = error
                    // 다음 자식 결과를 계속 본다.
                    continue
                }
            }
            throw lastError
        }
    }

    /// 현재 디바이스 시계에 offset을 적용한 추정 atomic time.
    func atomicNow(offset: NTPSample) -> Date {
        Date().addingTimeInterval(-offset.offsetSeconds)
    }

    private func query(host: String) async throws -> NTPSample {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<NTPSample, Error>) in
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: 123)
            )
            let conn = NWConnection(to: endpoint, using: .udp)
            let queue = DispatchQueue(label: "ticklab.ntp.\(host)")
            let resumed = ResumeGuard()

            // 타임아웃 가드
            queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                if resumed.tryResume() {
                    conn.cancel()
                    cont.resume(throwing: NTPError.timeout)
                }
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let packet = AtomicTimeService.makeRequestPacket()
                    let txTime = Date()
                    conn.send(content: packet, completion: .contentProcessed { sendErr in
                        if let sendErr {
                            if resumed.tryResume() {
                                conn.cancel()
                                cont.resume(throwing: sendErr)
                            }
                            return
                        }
                        conn.receiveMessage { data, _, _, recvErr in
                            let rxTime = Date()
                            if let recvErr {
                                if resumed.tryResume() {
                                    conn.cancel()
                                    cont.resume(throwing: recvErr)
                                }
                                return
                            }
                            guard let data, data.count >= 48 else {
                                if resumed.tryResume() {
                                    conn.cancel()
                                    cont.resume(throwing: NTPError.invalidResponse)
                                }
                                return
                            }
                            do {
                                let sample = try AtomicTimeService.parseSample(
                                    response: data,
                                    txTime: txTime,
                                    rxTime: rxTime
                                )
                                if resumed.tryResume() {
                                    conn.cancel()
                                    cont.resume(returning: sample)
                                }
                            } catch {
                                if resumed.tryResume() {
                                    conn.cancel()
                                    cont.resume(throwing: error)
                                }
                            }
                        }
                    })
                case .failed(let err):
                    if resumed.tryResume() {
                        conn.cancel()
                        cont.resume(throwing: err)
                    }
                case .cancelled:
                    if resumed.tryResume() {
                        cont.resume(throwing: NTPError.networkUnavailable)
                    }
                default:
                    break
                }
            }
            conn.start(queue: queue)
        }
    }

    /// LI=0, VN=4, Mode=3 (client), 나머지는 0. 길이 48 바이트.
    static func makeRequestPacket() -> Data {
        var packet = Data(count: 48)
        packet[0] = 0b00_100_011 // LI=0, VN=4, Mode=3
        return packet
    }

    /// SNTP 응답을 파싱해 offset/roundtrip 을 계산한다.
    /// originate timestamp: bytes 24..31 (= 우리가 보낸 transmit time = `txTime`)
    /// receive timestamp:   bytes 32..39 (서버가 받은 시각, T2)
    /// transmit timestamp:  bytes 40..47 (서버가 보낸 시각, T3)
    static func parseSample(response: Data, txTime: Date, rxTime: Date) throws -> NTPSample {
        guard response.count >= 48 else { throw NTPError.invalidResponse }
        let mode = response[0] & 0b0000_0111
        guard mode == 4 else { throw NTPError.invalidResponse } // server mode
        let stratum = response[1]
        // stratum 0 = Kiss-of-Death (서버가 거부 코드 보냄). stratum 16+ = unsynchronized.
        guard stratum > 0, stratum < 16 else { throw NTPError.invalidResponse }

        let serverReceive = readNTPTime(response, offset: 32)
        let serverTransmit = readNTPTime(response, offset: 40)
        // 1970-01-01 이전 timestamp 는 비정상 응답.
        guard serverReceive > 0, serverTransmit > 0 else { throw NTPError.invalidResponse }
        let t1 = txTime.timeIntervalSince1970
        let t2 = serverReceive
        let t3 = serverTransmit
        let t4 = rxTime.timeIntervalSince1970
        let offset = ((t2 - t1) + (t3 - t4)) / 2
        let delay = (t4 - t1) - (t3 - t2)
        return NTPSample(offsetSeconds: -offset, roundTripSeconds: delay, measuredAt: rxTime)
    }

    /// NTP 64-bit timestamp (seconds since 1900-01-01 UTC, fixed-point) → Unix epoch seconds.
    private static func readNTPTime(_ data: Data, offset: Int) -> TimeInterval {
        let secsRaw = (UInt32(data[offset]) << 24) |
                      (UInt32(data[offset + 1]) << 16) |
                      (UInt32(data[offset + 2]) << 8) |
                      UInt32(data[offset + 3])
        let fracRaw = (UInt32(data[offset + 4]) << 24) |
                      (UInt32(data[offset + 5]) << 16) |
                      (UInt32(data[offset + 6]) << 8) |
                      UInt32(data[offset + 7])
        let ntpEpochOffset: TimeInterval = 2_208_988_800 // seconds between 1900-01-01 and 1970-01-01
        let secs = TimeInterval(secsRaw) - ntpEpochOffset
        let frac = TimeInterval(fracRaw) / TimeInterval(UInt64(1) << 32)
        return secs + frac
    }
}

/// 한 번만 resume 되도록 보장하는 가드.
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func tryResume() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
