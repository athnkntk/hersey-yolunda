import XCTest
@testable import HerseyYolunda

final class StubURLProtocol: URLProtocol {
    static var status = 200
    static var responseBody = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class TransportTests: XCTestCase {
    private func client() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return APIClient(baseURL: URL(string: "https://example.test/v1")!, session: URLSession(configuration: configuration))
    }
    func testServerFailureIsNotSuccess() async {
        StubURLProtocol.status = 503
        StubURLProtocol.responseBody = Data("{\"code\":\"unavailable\",\"message\":\"Henüz gönderilemedi\"}".utf8)
        do {
            let _: Receipt = try await client().request("POST", "/me/checkins", authenticated: false)
            XCTFail("A failed request must never return a receipt")
        } catch let error as BackendError { XCTAssertEqual(error.code, "unavailable") }
        catch { XCTFail("Expected a typed backend error: \(error)") }
    }
    func testMalformedSuccessCannotBecomeCheckInReceipt() async {
        StubURLProtocol.status = 200
        StubURLProtocol.responseBody = Data("{}".utf8)
        do {
            let _: Receipt = try await client().request("POST", "/me/checkins", authenticated: false)
            XCTFail("Malformed success must not become a receipt")
        } catch { XCTAssertTrue(error is DecodingError) }
    }
    func testNonLocalPlainHTTPIsRejected() async {
        let unsafe = APIClient(baseURL: URL(string: "http://example.test/v1")!)
        do {
            let _: EmptyResponse = try await unsafe.request("GET", "/health", authenticated: false)
            XCTFail("Non-local plaintext is not allowed")
        } catch { XCTAssertTrue(error is LocalError) }
    }
}
