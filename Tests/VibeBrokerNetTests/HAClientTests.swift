import XCTest
@testable import VibeBrokerNet

// MARK: - URLProtocol stub

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "no handler", code: 0))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class HAClientTests: XCTestCase {
    private func makeClient() -> HAClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: cfg)
        return HAClient(
            baseURL: URL(string: "http://test.local:8123")!,
            token: "T0KEN",
            session: session
        )
    }

    func testCallServiceSendsPOST() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.handler = { req in
            capturedRequest = req
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data("[]".utf8))
        }

        let client = makeClient()
        try await client.callService(
            domain: "light",
            service: "turn_on",
            data: ["entity_id": "light.desk", "rgb_color": [255, 0, 0]]
        )

        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.url?.path, "/api/services/light/turn_on")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer T0KEN")

        let bodyData = capturedRequest!.httpBodyStreamData ?? capturedRequest!.httpBody!
        let body = try JSONSerialization.jsonObject(with: bodyData) as! [String: Any]
        XCTAssertEqual(body["entity_id"] as? String, "light.desk")
    }

    func testCallServiceThrowsOn4xx() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data("{}".utf8))
        }
        let client = makeClient()
        do {
            try await client.callService(domain: "light", service: "turn_on", data: [:])
            XCTFail("expected throw")
        } catch HAClient.Error.unauthorized {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testGetApiStatusReturnsTrueOn200() async throws {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data("{}".utf8))
        }
        let client = makeClient()
        let ok = try await client.getApiStatus()
        XCTAssertTrue(ok)
    }
}

extension URLRequest {
    var httpBodyStreamData: Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buf.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buf, maxLength: 4096)
            if read <= 0 { break }
            data.append(buf, count: read)
        }
        return data
    }
}
