import XCTest
@testable import VibeBrokerCore

final class SessionStoreTests: XCTestCase {
    private func event(_ name: HookName,
                       sessionId: String = "s1",
                       toolError: Bool = false,
                       message: String? = nil) -> HookEvent {
        HookEvent(hookName: name, sessionId: sessionId, cwd: "/p",
                  toolResponseIsError: toolError, notificationMessage: message)
    }

    func testRegistersOnSessionStart() async {
        let store = SessionStore(ttlSeconds: 300, now: { Date(timeIntervalSince1970: 0) })
        await store.handle(event(.sessionStart, sessionId: "s1"))

        let all = await store.snapshot()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all["s1"]?.state, .idle)
    }

    func testApplyTransition() async {
        let store = SessionStore(ttlSeconds: 300, now: { Date(timeIntervalSince1970: 0) })
        await store.handle(event(.sessionStart, sessionId: "s1"))
        await store.handle(event(.userPromptSubmit, sessionId: "s1"))

        let all = await store.snapshot()
        XCTAssertEqual(all["s1"]?.state, .working)
    }

    func testRemovesOnSessionEnd() async {
        let store = SessionStore(ttlSeconds: 300, now: { Date(timeIntervalSince1970: 0) })
        await store.handle(event(.sessionStart, sessionId: "s1"))
        await store.handle(event(.sessionEnd, sessionId: "s1"))

        let all = await store.snapshot()
        XCTAssertTrue(all.isEmpty)
    }

    func testAutoRegistersUnknownSession() async {
        let store = SessionStore(ttlSeconds: 300, now: { Date(timeIntervalSince1970: 0) })
        await store.handle(event(.userPromptSubmit, sessionId: "s1"))

        let all = await store.snapshot()
        XCTAssertEqual(all["s1"]?.state, .working)
    }

    func testTTLPrunesIdleSessions() async {
        var clock = Date(timeIntervalSince1970: 0)
        let store = SessionStore(ttlSeconds: 60, now: { clock })

        await store.handle(event(.sessionStart, sessionId: "s1"))
        clock = Date(timeIntervalSince1970: 120)
        let pruned = await store.pruneExpired()

        XCTAssertEqual(pruned, 1)
        let all = await store.snapshot()
        XCTAssertTrue(all.isEmpty)
    }

    func testTTLDoesNotPruneRecent() async {
        var clock = Date(timeIntervalSince1970: 0)
        let store = SessionStore(ttlSeconds: 60, now: { clock })

        await store.handle(event(.sessionStart, sessionId: "s1"))
        clock = Date(timeIntervalSince1970: 30)
        let pruned = await store.pruneExpired()

        XCTAssertEqual(pruned, 0)
    }

    func testMultipleSessionsTrackedIndependently() async {
        let store = SessionStore(ttlSeconds: 300, now: { Date(timeIntervalSince1970: 0) })
        await store.handle(event(.sessionStart, sessionId: "a"))
        await store.handle(event(.sessionStart, sessionId: "b"))
        await store.handle(event(.userPromptSubmit, sessionId: "a"))

        let all = await store.snapshot()
        XCTAssertEqual(all["a"]?.state, .working)
        XCTAssertEqual(all["b"]?.state, .idle)
    }
}
