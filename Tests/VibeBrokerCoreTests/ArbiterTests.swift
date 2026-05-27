import XCTest
@testable import VibeBrokerCore

final class ArbiterTests: XCTestCase {
    private func rec(_ state: State, id: String = UUID().uuidString, since: TimeInterval = 0) -> SessionRecord {
        let t = Date(timeIntervalSince1970: since)
        return SessionRecord(id: id, state: state, since: t, lastEventAt: t, cwd: nil)
    }

    func testEmptyReturnsIdle() {
        XCTAssertEqual(Arbiter.compute([:]), .idle)
    }

    func testSingleSessionReturnsItsState() {
        let store = ["s1": rec(.working)]
        XCTAssertEqual(Arbiter.compute(store), .working)
    }

    func testHighestPriorityWins() {
        let store = [
            "s1": rec(.working),
            "s2": rec(.needsAuth),
            "s3": rec(.idle),
        ]
        XCTAssertEqual(Arbiter.compute(store), .needsAuth)
    }

    func testErrorBeatsEverything() {
        let store = [
            "s1": rec(.needsAuth),
            "s2": rec(.error),
        ]
        XCTAssertEqual(Arbiter.compute(store), .error)
    }

    func testTieBreakerIsMostRecent() {
        let store = [
            "old": rec(.working, since: 0),
            "new": rec(.working, since: 100),
        ]
        XCTAssertEqual(Arbiter.compute(store), .working)
    }
}
