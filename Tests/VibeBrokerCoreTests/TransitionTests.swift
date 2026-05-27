import XCTest
@testable import VibeBrokerCore

final class TransitionTests: XCTestCase {
    private func event(_ name: HookName,
                       sessionId: String = "s1",
                       toolError: Bool = false,
                       message: String? = nil) -> HookEvent {
        HookEvent(
            hookName: name, sessionId: sessionId, cwd: nil,
            toolResponseIsError: toolError, notificationMessage: message
        )
    }

    func testSessionStartGoesToIdle() {
        XCTAssertEqual(Transition.apply(from: .idle, event: event(.sessionStart)), .idle)
        XCTAssertEqual(Transition.apply(from: .working, event: event(.sessionStart)), .idle)
    }

    func testUserPromptSubmitGoesToWorking() {
        XCTAssertEqual(Transition.apply(from: .idle, event: event(.userPromptSubmit)), .working)
        XCTAssertEqual(Transition.apply(from: .done, event: event(.userPromptSubmit)), .working)
    }

    func testPreToolUseKeepsWorking() {
        XCTAssertEqual(Transition.apply(from: .working, event: event(.preToolUse)), .working)
    }

    func testPostToolUseErrorGoesToError() {
        let e = event(.postToolUse, toolError: true)
        XCTAssertEqual(Transition.apply(from: .working, event: e), .error)
    }

    func testPostToolUseSuccessKeepsWorking() {
        XCTAssertEqual(Transition.apply(from: .working, event: event(.postToolUse)), .working)
    }

    func testNotificationWithPermissionGoesToNeedsAuth() {
        let e = event(.notification, message: "Claude needs your permission to use Bash")
        XCTAssertEqual(Transition.apply(from: .working, event: e), .needsAuth)
    }

    func testNotificationWithApproveGoesToNeedsAuth() {
        let e = event(.notification, message: "Approve this command?")
        XCTAssertEqual(Transition.apply(from: .working, event: e), .needsAuth)
    }

    func testNotificationGenericGoesToWaitingInput() {
        let e = event(.notification, message: "Claude is waiting for your input")
        XCTAssertEqual(Transition.apply(from: .working, event: e), .waitingInput)
    }

    func testPreCompactGoesToCompacting() {
        XCTAssertEqual(Transition.apply(from: .working, event: event(.preCompact)), .compacting)
    }

    func testCompactingExitsOnNextActivity() {
        XCTAssertEqual(Transition.apply(from: .compacting, event: event(.userPromptSubmit)), .working)
        XCTAssertEqual(Transition.apply(from: .compacting, event: event(.preToolUse)), .working)
        XCTAssertEqual(Transition.apply(from: .compacting, event: event(.postToolUse)), .working)
        XCTAssertEqual(Transition.apply(from: .compacting, event: event(.stop)), .done)
    }

    func testStopGoesToDone() {
        XCTAssertEqual(Transition.apply(from: .working, event: event(.stop)), .done)
    }

    func testFallbackNotificationGoesToNeedsAuthWhenMessageMissing() {
        let e = event(.notification, message: nil)
        XCTAssertEqual(Transition.apply(from: .working, event: e), .needsAuth)
    }
}
