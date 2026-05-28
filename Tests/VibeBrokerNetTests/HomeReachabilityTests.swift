import XCTest
@testable import VibeBrokerNet
@testable import VibeBrokerCore

final class HomeReachabilityTests: XCTestCase {
    func testReachableIfProbeSucceeds() async throws {
        let probe = MockProbe(result: true)
        let reach = HomeReachability(probe: probe.probe)
        let result = await reach.checkNow()
        XCTAssertTrue(result)
        XCTAssertEqual(probe.callCount, 1)
    }

    func testNotReachableIfProbeFails() async throws {
        let probe = MockProbe(result: false)
        let reach = HomeReachability(probe: probe.probe)
        let result = await reach.checkNow()
        XCTAssertFalse(result)
    }

    func testStreamYieldsOnCheckNow() async throws {
        let probe = MockProbe(result: true)
        let reach = HomeReachability(probe: probe.probe)
        let stream = await reach.stream()

        Task {
            _ = await reach.checkNow()
            _ = await reach.checkNow()
        }

        var collected: [Bool] = []
        for await value in stream {
            collected.append(value)
            if collected.count >= 1 { break }
        }
        XCTAssertEqual(collected.first, true)
    }
}

final class MockProbe: @unchecked Sendable {
    private let result: Bool
    private(set) var callCount = 0
    private let lock = NSLock()
    init(result: Bool) { self.result = result }
    func probe() async -> Bool {
        lock.lock(); defer { lock.unlock() }
        callCount += 1
        return result
    }
}
