import XCTest
@testable import VibeBrokerNet

final class HTTPListenerTests: XCTestCase {
    func testListenerRoutesRequestToHandler() async throws {
        let listener = HTTPListener(port: 0) { request in
            HTTPResponse(status: 200, body: Data("hi from \(request.path)".utf8))
        }
        try await listener.start()
        defer { Task { await listener.stop() } }

        let port = await listener.boundPort()
        let url = URL(string: "http://127.0.0.1:\(port)/health")!

        let (data, response) = try await URLSession.shared.data(from: url)
        let http = response as! HTTPURLResponse
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), "hi from /health")
    }

    func testListenerHandlesPostBody() async throws {
        var capturedBody: Data?
        let listener = HTTPListener(port: 0) { request in
            capturedBody = request.body
            return HTTPResponse(status: 204, body: Data())
        }
        try await listener.start()
        defer { Task { await listener.stop() } }

        let port = await listener.boundPort()
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/event")!)
        req.httpMethod = "POST"
        req.httpBody = Data("{\"hello\":1}".utf8)

        let (_, response) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((response as! HTTPURLResponse).statusCode, 204)
        XCTAssertEqual(String(data: capturedBody ?? Data(), encoding: .utf8), #"{"hello":1}"#)
    }
}

extension HTTPListenerTests {
    func testListenerStillServesLoopbackAfterFix() async throws {
        // Regression: after adding loopback filtering, 127.0.0.1 connections still work.
        let listener = HTTPListener(port: 0) { _ in
            HTTPResponse(status: 200, body: Data("ok".utf8))
        }
        try await listener.start()
        defer { Task { await listener.stop() } }

        let port = await listener.boundPort()
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/")!)
        XCTAssertEqual(String(data: data, encoding: .utf8), "ok")
    }
}
