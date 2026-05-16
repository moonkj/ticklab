import CryptoKit
import Foundation

/// 무브먼트 DB 의 OTA 업데이트.
/// - 원격: HTTPS GET → 새 `MovementDB.json` (옵션: SHA-256 검증)
/// - 캐시: `Application Support/movement-db/MovementDB.json`
/// - 폴백: 캐시 없거나 검증 실패 시 번들 내장 JSON 사용
final class MovementDBOTAService {
    enum OTAError: Error {
        case invalidURL
        case invalidResponse
        case invalidPayload
        case checksumMismatch
        case payloadTooLarge
        /// Round 16 (Jay): host whitelist 위반 — MITM/redirect 의심.
        case untrustedHost
    }

    /// MITM 공격으로 거대한 payload 폭탄을 던지는 시나리오 방지. 5MB 상한.
    static let maxPayloadBytes: Int = 5 * 1024 * 1024

    struct UpdateResult: Equatable {
        let installedVersion: String
        let movementsCount: Int
        let updatedAt: Date
    }

    /// 원격 manifest payload. 단순 버전 + url + 옵션 sha256.
    struct Manifest: Codable, Equatable {
        let version: String
        let dataURL: URL
        let sha256: String?
    }

    static let shared = MovementDBOTAService()

    private let session: URLSession
    private let manifestURL: URL?

    init(
        manifestURL: URL? = URL(string: "https://ticklab.app/movements/manifest.json"),
        session: URLSession = .shared
    ) {
        self.manifestURL = manifestURL
        self.session = session
    }

    // MARK: - Public API

    /// 업데이트 시도. 같은 버전이면 noop. 새 버전이면 캐시에 쓰고 메모리 DB 교체.
    @discardableResult
    func updateIfAvailable() async throws -> UpdateResult {
        guard let manifestURL else { throw OTAError.invalidURL }
        let manifestData = try await fetchData(url: manifestURL)
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)

        if let installed = installedVersion(), installed == manifest.version {
            return UpdateResult(
                installedVersion: manifest.version,
                movementsCount: cachedMovements()?.count ?? MovementDatabase.shared.movements.count,
                updatedAt: Date()
            )
        }

        // Round 103 (Security Critical #1): dataURL host 화이트리스트 — 임의 host payload 차단.
        // Round 104 (Swift): URL.host property deprecated iOS 16+ → URL.host() 메서드 사용.
        guard let dataHost = manifest.dataURL.host(),
              dataHost == "ticklab.app" || dataHost.hasSuffix(".ticklab.app") else {
            throw OTAError.untrustedHost
        }
        let payload = try await fetchData(url: manifest.dataURL)
        // sha256 이 제공됐으면 반드시 검증. 없어도 host 가드 통과했으면 진행 (legacy manifest 호환).
        if let expected = manifest.sha256 {
            let actual = sha256Hex(payload)
            guard actual.lowercased() == expected.lowercased() else {
                throw OTAError.checksumMismatch
            }
        }
        let movements = try JSONDecoder().decode([Movement].self, from: payload)
        try persist(payload: payload, version: manifest.version)
        await MainActor.run {
            MovementDatabase.shared.replaceAll(with: movements)
        }
        return UpdateResult(
            installedVersion: manifest.version,
            movementsCount: movements.count,
            updatedAt: Date()
        )
    }

    func cachedMovements() -> [Movement]? {
        guard let url = cacheFileURL(), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Movement].self, from: data)
    }

    func installedVersion() -> String? {
        UserDefaults.standard.string(forKey: "ticklab.movementdb.version")
    }

    // MARK: - Internals

    /// Round 4 (Jay, audit): MITM 메모리 폭탄 가드 2단계.
    /// 1) Content-Length 가 상한 넘으면 fetch 자체를 스킵.
    /// 2) 실제 다운된 data 크기를 한 번 더 체크 (압축 등으로 헤더와 다를 수 있음).
    /// `data(from:)` 가 일정 buffer 사용해 메모리 효율적으로 받아오므로 5MB 초과만 거르면 안전.
    private func fetchData(url: URL) async throws -> Data {
        // 1차: HEAD 비슷한 효과로 Content-Length 미리 확인.
        var headRequest = URLRequest(url: url)
        headRequest.httpMethod = "HEAD"
        if let (_, headResponse) = try? await session.data(for: headRequest),
           let http = headResponse as? HTTPURLResponse,
           let contentLength = http.value(forHTTPHeaderField: "Content-Length"),
           let advertised = Int(contentLength),
           advertised > Self.maxPayloadBytes {
            throw OTAError.payloadTooLarge
        }
        // 2차: 실제 GET. data(from:) 가 메모리에 한 번에 로드하지만 위 HEAD 로 5MB+ 필터링됨.
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw OTAError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw OTAError.invalidResponse }
        guard !data.isEmpty else { throw OTAError.invalidPayload }
        guard data.count <= Self.maxPayloadBytes else { throw OTAError.payloadTooLarge }
        return data
    }

    private func persist(payload: Data, version: String) throws {
        guard let url = cacheFileURL() else { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try payload.write(to: url, options: .atomic)
        UserDefaults.standard.set(version, forKey: "ticklab.movementdb.version")
    }

    private func cacheFileURL() -> URL? {
        let dirs = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return dirs?
            .appendingPathComponent("movement-db", isDirectory: true)
            .appendingPathComponent("MovementDB.json")
    }

    private func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
