import XCTest
@testable import VibeBrokerCore

final class StateTests: XCTestCase {
    func testPriorityOrder() {
        // ERROR > NEEDS_AUTH > WAITING_INPUT > COMPACTING > WORKING > DONE > IDLE
        XCTAssertGreaterThan(State.error.priority, State.needsAuth.priority)
        XCTAssertGreaterThan(State.needsAuth.priority, State.waitingInput.priority)
        XCTAssertGreaterThan(State.waitingInput.priority, State.compacting.priority)
        XCTAssertGreaterThan(State.compacting.priority, State.working.priority)
        XCTAssertGreaterThan(State.working.priority, State.done.priority)
        XCTAssertGreaterThan(State.done.priority, State.idle.priority)
    }

    func testAllCasesExist() {
        XCTAssertEqual(State.allCases.count, 7)
    }

    func testSerializedName() {
        XCTAssertEqual(State.idle.serializedName, "idle")
        XCTAssertEqual(State.waitingInput.serializedName, "waiting_input")
        XCTAssertEqual(State.needsAuth.serializedName, "needs_auth")
    }
}
