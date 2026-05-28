import XCTest
@testable import VibeBrokerNet
@testable import VibeBrokerCore

final class ScenePackDriverTests: XCTestCase {
    func testRenderCallsSceneTurnOn() async {
        let spy = SpyHAClient()
        let driver = ScenePackDriver(client: spy)

        await driver.render(.working)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(spy.calls.first?.domain, "scene")
        XCTAssertEqual(spy.calls.first?.service, "turn_on")
        XCTAssertEqual(spy.calls.first?.entityId, "scene.vibelight_working")

        await driver.cancel()
    }

    func testRenderUsesCorrectSceneNameForEachState() async {
        let states: [(VibeBrokerCore.State, String)] = [
            (.idle, "scene.vibelight_idle"),
            (.done, "scene.vibelight_done"),
            (.working, "scene.vibelight_working"),
            (.compacting, "scene.vibelight_compacting"),
            (.waitingInput, "scene.vibelight_waiting_input"),
            (.needsAuth, "scene.vibelight_needs_auth"),
            (.error, "scene.vibelight_error"),
        ]
        for (state, expectedEntity) in states {
            let spy = SpyHAClient()
            let driver = ScenePackDriver(client: spy)
            await driver.render(state)
            try? await Task.sleep(nanoseconds: 50_000_000)
            XCTAssertEqual(spy.calls.first?.entityId, expectedEntity,
                           "wrong scene for \(state)")
            await driver.cancel()
        }
    }
}
