import XCTest
@testable import VibeBrokerNet
@testable import VibeBrokerCore

final class SpyHAClient: LightServiceCaller, @unchecked Sendable {
    struct Call: Equatable {
        let domain: String
        let service: String
        let entityId: String?
        let rgbColor: [Int]?
        let brightness: Int?
    }
    private(set) var calls: [Call] = []
    private let lock = NSLock()

    func callService(domain: String, service: String, data: [String: Any]) async throws {
        lock.lock(); defer { lock.unlock() }
        calls.append(Call(
            domain: domain,
            service: service,
            entityId: data["entity_id"] as? String,
            rgbColor: data["rgb_color"] as? [Int],
            brightness: data["brightness"] as? Int
        ))
    }
}

final class BrokerEmulatedDriverSolidTests: XCTestCase {
    private let workingColor = ColorConfig(rgb: [40, 120, 255], brightness: 200, effect: .breathe)
    private let needsAuthColor = ColorConfig(rgb: [255, 30, 30], brightness: 230, effect: .solid)

    private func makeConfig() -> Config {
        Config(
            broker: BrokerConfig(port: 17345),
            homeAssistant: HAConfig(url: URL(string: "http://h")!, token: "t", lightEntity: "light.x"),
            behavior: BehaviorConfig(
                sessionTtlSeconds: 300, errorAutoClearSeconds: 5,
                doneBlinkSeconds: 2, waitingInputBlinkSeconds: 3, debounceMillis: 100
            ),
            colors: [
                .idle: ColorConfig(rgb: [80, 30, 120], brightness: 80, effect: .solid),
                .working: workingColor,
                .compacting: workingColor,
                .waitingInput: workingColor,
                .needsAuth: needsAuthColor,
                .error: needsAuthColor,
                .done: workingColor,
            ]
        )
    }

    func testSolidEffectFiresOneCall() async {
        let spy = SpyHAClient()
        let driver = BrokerEmulatedDriver(client: spy, config: makeConfig())

        await driver.render(.needsAuth)
        // Allow async effect Task to run.
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(spy.calls.first?.domain, "light")
        XCTAssertEqual(spy.calls.first?.service, "turn_on")
        XCTAssertEqual(spy.calls.first?.rgbColor, [255, 30, 30])
        XCTAssertEqual(spy.calls.first?.brightness, 230)

        await driver.cancel()
    }
}

final class BrokerEmulatedDriverBreatheTests: XCTestCase {
    private func makeConfig() -> Config {
        BrokerEmulatedDriverSolidTests().makeConfigForBreathe()
    }

    func testBreatheLoopAlternatesBrightness() async {
        let spy = SpyHAClient()
        let driver = BrokerEmulatedDriver(client: spy, config: makeConfig())

        await driver.render(.working)
        try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 s -> ~3 ticks

        await driver.cancel()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertGreaterThanOrEqual(spy.calls.count, 2)
        let brightnessValues = Set(spy.calls.compactMap(\.brightness))
        XCTAssertGreaterThanOrEqual(brightnessValues.count, 2,
            "breathe should produce at least two brightness levels")
    }
}

extension BrokerEmulatedDriverSolidTests {
    func makeConfigForBreathe() -> Config { makeConfig() }
}
