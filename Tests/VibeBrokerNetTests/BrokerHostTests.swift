import XCTest
@testable import VibeBrokerNet
@testable import VibeBrokerCore

final class BrokerHostTests: XCTestCase {
    private func makeConfig(port: UInt16 = 0) -> Config {
        let base = BrokerEmulatedDriverSolidTests().makeConfigForBreathe()
        return Config(
            broker: BrokerConfig(port: port),
            homeAssistant: base.homeAssistant,
            behavior: base.behavior,
            colors: base.colors
        )
    }

    func testHostStartsAndExposesBoundPort() async throws {
        let host = BrokerHost(config: makeConfig())
        try await host.start()
        defer { Task { await host.stop() } }

        let port = await host.boundPort()
        XCTAssertGreaterThan(port, 0)
    }

    func testHostHealthEndpointWorks() async throws {
        let host = BrokerHost(config: makeConfig())
        try await host.start()
        defer { Task { await host.stop() } }

        let port = await host.boundPort()
        let (_, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/health")!)
        XCTAssertEqual((response as! HTTPURLResponse).statusCode, 200)
    }

    func testHostObserverFiresOnHookEvent() async throws {
        let host = BrokerHost(config: makeConfig())
        let received = ObserverRecorder()
        await host.setObserver { s in await received.append(s) }
        try await host.start()
        defer { Task { await host.stop() } }

        let port = await host.boundPort()
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/event?hook=UserPromptSubmit")!)
        req.httpMethod = "POST"
        req.httpBody = Data(#"{"session_id":"abc"}"#.utf8)
        _ = try await URLSession.shared.data(for: req)
        try? await Task.sleep(nanoseconds: 200_000_000)

        let observed = await received.snapshot()
        XCTAssertEqual(observed, [.working])
    }

    func testHostPauseTogglesDriver() async throws {
        let host = BrokerHost(config: makeConfig())
        try await host.start()
        defer { Task { await host.stop() } }

        await host.setPaused(true)
        let pausedTrue = await host.isPaused()
        XCTAssertTrue(pausedTrue)
        await host.setPaused(false)
        let pausedFalse = await host.isPaused()
        XCTAssertFalse(pausedFalse)
    }
}
