import XCTest
@testable import VibeBrokerNet
@testable import VibeBrokerCore

final class EventRouterTests: XCTestCase {
    private func makeConfig() -> Config {
        BrokerEmulatedDriverSolidTests().makeConfigForBreathe()
    }

    func testEventEndpointAppliesTransitionAndRenders() async throws {
        let store = SessionStore(ttlSeconds: 300)
        let driver = SpyDriver()
        let router = EventRouter(store: store, driver: driver, config: makeConfig())

        let body = #"{"session_id":"s1","cwd":"/p"}"#
        let request = HTTPRequest(
            method: "POST", path: "/event",
            query: ["hook": "UserPromptSubmit"],
            headers: [:], body: Data(body.utf8)
        )

        let response = await router.handle(request)
        XCTAssertEqual(response.status, 204)

        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(driver.lastRendered, .working)
    }

    func testEventEndpointHandlesUnknownHook() async {
        let store = SessionStore(ttlSeconds: 300)
        let driver = SpyDriver()
        let router = EventRouter(store: store, driver: driver, config: makeConfig())

        let request = HTTPRequest(
            method: "POST", path: "/event",
            query: ["hook": "Bogus"], headers: [:], body: Data("{}".utf8)
        )
        let response = await router.handle(request)
        XCTAssertEqual(response.status, 400)
    }

    func testErrorAutoClearsAfterTimeout() async throws {
        let store = SessionStore(ttlSeconds: 300)
        let driver = SpyDriver()
        var cfg = makeConfig()
        cfg = Config(
            broker: cfg.broker, homeAssistant: cfg.homeAssistant,
            behavior: BehaviorConfig(
                sessionTtlSeconds: cfg.behavior.sessionTtlSeconds,
                errorAutoClearSeconds: 0.3,
                doneBlinkSeconds: cfg.behavior.doneBlinkSeconds,
                waitingInputBlinkSeconds: cfg.behavior.waitingInputBlinkSeconds,
                debounceMillis: 0
            ),
            colors: cfg.colors
        )
        let router = EventRouter(store: store, driver: driver, config: cfg)

        let body = #"{"session_id":"s1","tool_response":{"is_error":true}}"#
        let request = HTTPRequest(
            method: "POST", path: "/event",
            query: ["hook": "PostToolUse"], headers: [:], body: Data(body.utf8)
        )
        _ = await router.handle(request)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(driver.lastRendered, .error)

        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(driver.lastRendered, .idle,
            "ERROR should auto-clear to IDLE after errorAutoClearSeconds")
    }
}

final class SpyDriver: LightDriver, @unchecked Sendable {
    private(set) var lastRendered: State?
    private let lock = NSLock()
    func render(_ state: State) async {
        lock.lock(); defer { lock.unlock() }
        lastRendered = state
    }
    func cancel() async {}
}
