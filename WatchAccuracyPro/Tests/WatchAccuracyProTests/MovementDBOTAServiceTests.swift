import CryptoKit
import XCTest
@testable import WatchAccuracyPro

final class MovementDBOTAServiceTests: XCTestCase {
    private let manifestURL = URL(string: "https://test.ticklab.app/movements/manifest.json")!
    private let dataURL = URL(string: "https://test.ticklab.app/movements/MovementDB.json")!

    override func tearDown() {
        super.tearDown()
        MockURLProtocol.reset()
        UserDefaults.standard.removeObject(forKey: "ticklab.movementdb.version")
    }

    private func makeService() -> MovementDBOTAService {
        let config = MockURLProtocol.makeSessionConfig()
        let session = URLSession(configuration: config)
        return MovementDBOTAService(manifestURL: manifestURL, session: session)
    }

    private func makeMovementJSON() -> Data {
        let payload = #"""
        [
          {
            "id": "TEST_M1", "brandFamilies": ["Test"], "bph": 28800,
            "liftAngleDegrees": 52.0, "escapement": "swissLever",
            "typicalAmplitudeMin": 270.0, "typicalAmplitudeMax": 315.0,
            "coscToleranceMin": -4.0, "coscToleranceMax": 6.0,
            "confidenceLabel": "high"
          }
        ]
        """#
        return Data(payload.utf8)
    }

    func test_update_succeeds_with_valid_manifest_and_payload() async throws {
        let movementsData = makeMovementJSON()
        let manifestPayload = try JSONEncoder().encode(MovementDBOTAService.Manifest(
            version: "2026-05-10-test",
            dataURL: dataURL,
            sha256: nil
        ))
        MockURLProtocol.register({ _ in
            (HTTPURLResponse(url: self.manifestURL, statusCode: 200, httpVersion: nil, headerFields: nil)!, manifestPayload)
        }, for: manifestURL)
        MockURLProtocol.register({ _ in
            (HTTPURLResponse(url: self.dataURL, statusCode: 200, httpVersion: nil, headerFields: nil)!, movementsData)
        }, for: dataURL)

        let result = try await makeService().updateIfAvailable()
        XCTAssertEqual(result.installedVersion, "2026-05-10-test")
        XCTAssertEqual(result.movementsCount, 1)
    }

    func test_update_succeeds_with_correct_sha256() async throws {
        let movementsData = makeMovementJSON()
        let sha = SHA256.hash(data: movementsData).map { String(format: "%02x", $0) }.joined()
        let manifestPayload = try JSONEncoder().encode(MovementDBOTAService.Manifest(
            version: "checksum-test",
            dataURL: dataURL,
            sha256: sha
        ))
        MockURLProtocol.register({ _ in
            (HTTPURLResponse(url: self.manifestURL, statusCode: 200, httpVersion: nil, headerFields: nil)!, manifestPayload)
        }, for: manifestURL)
        MockURLProtocol.register({ _ in
            (HTTPURLResponse(url: self.dataURL, statusCode: 200, httpVersion: nil, headerFields: nil)!, movementsData)
        }, for: dataURL)

        let result = try await makeService().updateIfAvailable()
        XCTAssertEqual(result.installedVersion, "checksum-test")
    }

    func test_update_throws_on_sha256_mismatch() async throws {
        let movementsData = makeMovementJSON()
        let manifestPayload = try JSONEncoder().encode(MovementDBOTAService.Manifest(
            version: "bad-checksum",
            dataURL: dataURL,
            sha256: "deadbeef"
        ))
        MockURLProtocol.register({ _ in
            (HTTPURLResponse(url: self.manifestURL, statusCode: 200, httpVersion: nil, headerFields: nil)!, manifestPayload)
        }, for: manifestURL)
        MockURLProtocol.register({ _ in
            (HTTPURLResponse(url: self.dataURL, statusCode: 200, httpVersion: nil, headerFields: nil)!, movementsData)
        }, for: dataURL)

        do {
            _ = try await makeService().updateIfAvailable()
            XCTFail("checksum mismatch 시 throw 해야 한다")
        } catch let err as MovementDBOTAService.OTAError {
            XCTAssertEqual(err, .checksumMismatch)
        } catch {
            XCTFail("expected OTAError.checksumMismatch — got \(error)")
        }
    }

    func test_update_throws_on_payload_too_large() async throws {
        let huge = Data(count: MovementDBOTAService.maxPayloadBytes + 1)
        let manifestPayload = try JSONEncoder().encode(MovementDBOTAService.Manifest(
            version: "huge", dataURL: dataURL, sha256: nil
        ))
        MockURLProtocol.register({ _ in
            (HTTPURLResponse(url: self.manifestURL, statusCode: 200, httpVersion: nil, headerFields: nil)!, manifestPayload)
        }, for: manifestURL)
        MockURLProtocol.register({ _ in
            (HTTPURLResponse(url: self.dataURL, statusCode: 200, httpVersion: nil, headerFields: nil)!, huge)
        }, for: dataURL)

        do {
            _ = try await makeService().updateIfAvailable()
            XCTFail("payload too large 시 throw 해야 한다")
        } catch let err as MovementDBOTAService.OTAError {
            XCTAssertEqual(err, .payloadTooLarge)
        } catch {
            XCTFail("expected payloadTooLarge — got \(error)")
        }
    }
}

private enum OTAError: Error { case nothing }
