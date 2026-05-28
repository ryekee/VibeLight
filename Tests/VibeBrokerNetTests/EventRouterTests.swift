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

final class EventRouterEndpointTests: XCTestCase {
    private func makeConfig() -> Config { BrokerEmulatedDriverSolidTests().makeConfigForBreathe() }

    func testStateEndpointReturnsCurrentSnapshot() async throws {
        let store = SessionStore(ttlSeconds: 300)
        await store.handle(HookEvent(
            hookName: .userPromptSubmit, sessionId: "s1", cwd: "/p",
            toolResponseIsError: false, notificationMessage: nil
        ))
        let driver = SpyDriver()
        let router = EventRouter(store: store, driver: driver, config: makeConfig())

        let req = HTTPRequest(method: "GET", path: "/state", query: [:], headers: [:], body: Data())
        let resp = await router.handle(req)
        XCTAssertEqual(resp.status, 200)
        let json = try JSONSerialization.jsonObject(with: resp.body) as! [String: Any]
        XCTAssertEqual(json["effective"] as? String, "working")
    }

    func testHealthEndpoint() async {
        let store = SessionStore(ttlSeconds: 300)
        let router = EventRouter(store: store, driver: SpyDriver(), config: makeConfig())
        let req = HTTPRequest(method: "GET", path: "/health", query: [:], headers: [:], body: Data())
        let resp = await router.handle(req)
        XCTAssertEqual(resp.status, 200)
    }

    func testTestEndpointTriggersDriver() async {
        let store = SessionStore(ttlSeconds: 300)
        let driver = SpyDriver()
        let router = EventRouter(store: store, driver: driver, config: makeConfig())
        let req = HTTPRequest(method: "POST", path: "/test",
                              query: ["state": "needs_auth"], headers: [:], body: Data())
        let resp = await router.handle(req)
        XCTAssertEqual(resp.status, 204)
        XCTAssertEqual(driver.lastRendered, .needsAuth)
    }

    func testUnknownEndpointReturns404() async {
        let store = SessionStore(ttlSeconds: 300)
        let router = EventRouter(store: store, driver: SpyDriver(), config: makeConfig())
        let req = HTTPRequest(method: "GET", path: "/nope", query: [:], headers: [:], body: Data())
        let resp = await router.handle(req)
        XCTAssertEqual(resp.status, 404)
    }
}

final class EventRouterObserverTests: XCTestCase {
    func testObserverReceivesEffectiveStateOnEvent() async throws {
        let store = SessionStore(ttlSeconds: 300)
        let driver = SpyDriver()
        var cfg = BrokerEmulatedDriverSolidTests().makeConfigForBreathe()
        cfg = Config(
            broker: cfg.broker, homeAssistant: cfg.homeAssistant,
            behavior: BehaviorConfig(
                sessionTtlSeconds: cfg.behavior.sessionTtlSeconds,
                errorAutoClearSeconds: cfg.behavior.errorAutoClearSeconds,
                doneBlinkSeconds: cfg.behavior.doneBlinkSeconds,
                waitingInputBlinkSeconds: cfg.behavior.waitingInputBlinkSeconds,
                debounceMillis: 0
            ),
            colors: cfg.colors
        )
        let router = EventRouter(store: store, driver: driver, config: cfg)

        let received = ObserverRecorder()
        await router.setObserver { state in await received.append(state) }

        let body = #"{"session_id":"s1"}"#
        let request = HTTPRequest(
            method: "POST", path: "/event",
            query: ["hook": "UserPromptSubmit"],
            headers: [:], body: Data(body.utf8)
        )
        _ = await router.handle(request)
        try? await Task.sleep(nanoseconds: 100_000_000)

        let states = await received.snapshot()
        XCTAssertEqual(states, [.working])
    }
}

final actor ObserverRecorder {
    private(set) var observed: [State] = []
    func append(_ s: State) { observed.append(s) }
    func snapshot() -> [State] { observed }
}

final class EventRouterPauseTests: XCTestCase {
    func testPausedRouterSkipsDriverButNotifiesObserver() async throws {
        let store = SessionStore(ttlSeconds: 300)
        let driver = SpyDriver()
        var cfg = BrokerEmulatedDriverSolidTests().makeConfigForBreathe()
        cfg = Config(
            broker: cfg.broker, homeAssistant: cfg.homeAssistant,
            behavior: BehaviorConfig(
                sessionTtlSeconds: cfg.behavior.sessionTtlSeconds,
                errorAutoClearSeconds: cfg.behavior.errorAutoClearSeconds,
                doneBlinkSeconds: cfg.behavior.doneBlinkSeconds,
                waitingInputBlinkSeconds: cfg.behavior.waitingInputBlinkSeconds,
                debounceMillis: 0
            ),
            colors: cfg.colors
        )
        let router = EventRouter(store: store, driver: driver, config: cfg)
        let received = ObserverRecorder()
        await router.setObserver { s in await received.append(s) }

        await router.setPaused(true)

        let request = HTTPRequest(
            method: "POST", path: "/event",
            query: ["hook": "UserPromptSubmit"], headers: [:],
            body: Data(#"{"session_id":"s1"}"#.utf8)
        )
        _ = await router.handle(request)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(driver.lastRendered, "driver must not render while paused")
        let observed = await received.snapshot()
        XCTAssertEqual(observed, [.working], "observer should still receive state while paused")
    }

    func testResumeImmediatelyRenders() async throws {
        let store = SessionStore(ttlSeconds: 300)
        let driver = SpyDriver()
        var cfg = BrokerEmulatedDriverSolidTests().makeConfigForBreathe()
        cfg = Config(
            broker: cfg.broker, homeAssistant: cfg.homeAssistant,
            behavior: BehaviorConfig(
                sessionTtlSeconds: cfg.behavior.sessionTtlSeconds,
                errorAutoClearSeconds: cfg.behavior.errorAutoClearSeconds,
                doneBlinkSeconds: cfg.behavior.doneBlinkSeconds,
                waitingInputBlinkSeconds: cfg.behavior.waitingInputBlinkSeconds,
                debounceMillis: 0
            ),
            colors: cfg.colors
        )
        let router = EventRouter(store: store, driver: driver, config: cfg)

        await router.setPaused(true)
        let request = HTTPRequest(
            method: "POST", path: "/event",
            query: ["hook": "UserPromptSubmit"], headers: [:],
            body: Data(#"{"session_id":"s1"}"#.utf8)
        )
        _ = await router.handle(request)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(driver.lastRendered)

        await router.setPaused(false)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(driver.lastRendered, .working, "resume should re-render current effective state")
    }
}
