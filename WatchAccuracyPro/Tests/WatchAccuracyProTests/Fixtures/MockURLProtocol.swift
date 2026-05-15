import Foundation

/// 테스트 격리용 URLProtocol — 등록된 핸들러로 응답을 만들어 반환.
/// 사용: `let session = URLSession(configuration: MockURLProtocol.makeSessionConfig())`
final class MockURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    nonisolated(unsafe) static var requestHandlers: [URL: Handler] = [:]

    static func register(_ handler: @escaping Handler, for url: URL) {
        requestHandlers[url] = handler
    }

    static func reset() {
        requestHandlers.removeAll()
    }

    static func makeSessionConfig() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self] + (config.protocolClasses ?? [])
        return config
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return requestHandlers[url] != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let handler = MockURLProtocol.requestHandlers[url] else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
