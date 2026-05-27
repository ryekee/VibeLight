import XCTest
@testable import VibeBrokerNet

final class HTTPRequestTests: XCTestCase {
    func testParseSimpleGET() throws {
        let raw = "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let req = try HTTPRequest.parse(Data(raw.utf8))
        XCTAssertEqual(req.method, "GET")
        XCTAssertEqual(req.path, "/health")
        XCTAssertTrue(req.query.isEmpty)
        XCTAssertTrue(req.body.isEmpty)
    }

    func testParseQueryString() throws {
        let raw = "POST /event?hook=PreToolUse&x=1 HTTP/1.1\r\nContent-Length: 0\r\n\r\n"
        let req = try HTTPRequest.parse(Data(raw.utf8))
        XCTAssertEqual(req.path, "/event")
        XCTAssertEqual(req.query["hook"], "PreToolUse")
        XCTAssertEqual(req.query["x"], "1")
    }

    func testParsePostBody() throws {
        let body = #"{"session_id":"s1"}"#
        let raw = "POST /event HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let req = try HTTPRequest.parse(Data(raw.utf8))
        XCTAssertEqual(String(data: req.body, encoding: .utf8), body)
    }

    func testMalformedThrows() {
        let raw = "garbage"
        XCTAssertThrowsError(try HTTPRequest.parse(Data(raw.utf8)))
    }
}
