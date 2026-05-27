import XCTest
@testable import VibeBrokerCore

final class EventTests: XCTestCase {
    func testParseSessionStart() throws {
        let json = #"{"session_id":"abc","transcript_path":"/tmp/t.json","cwd":"/Users/u/p"}"#
        let event = try HookEvent.parse(hookName: "SessionStart", body: Data(json.utf8))

        XCTAssertEqual(event.hookName, .sessionStart)
        XCTAssertEqual(event.sessionId, "abc")
        XCTAssertEqual(event.cwd, "/Users/u/p")
    }

    func testPostToolUseErrorDetection() throws {
        let json = #"""
        {"session_id":"abc","tool_response":{"is_error":true,"error":"boom"}}
        """#
        let event = try HookEvent.parse(hookName: "PostToolUse", body: Data(json.utf8))

        XCTAssertEqual(event.hookName, .postToolUse)
        XCTAssertTrue(event.toolResponseIsError)
    }

    func testPostToolUseSuccess() throws {
        let json = #"{"session_id":"abc","tool_response":{"output":"ok"}}"#
        let event = try HookEvent.parse(hookName: "PostToolUse", body: Data(json.utf8))

        XCTAssertFalse(event.toolResponseIsError)
    }

    func testNotificationMessage() throws {
        let json = #"{"session_id":"abc","message":"Claude needs your permission to use Bash"}"#
        let event = try HookEvent.parse(hookName: "Notification", body: Data(json.utf8))

        XCTAssertEqual(event.notificationMessage, "Claude needs your permission to use Bash")
    }

    func testUnknownHookNameThrows() {
        XCTAssertThrowsError(try HookEvent.parse(hookName: "BogusHook", body: Data("{}".utf8)))
    }

    func testMissingSessionIdThrows() {
        XCTAssertThrowsError(try HookEvent.parse(hookName: "SessionStart", body: Data("{}".utf8)))
    }
}
