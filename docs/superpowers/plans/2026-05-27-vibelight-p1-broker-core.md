# VibeLight P1: Headless Broker Core — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a headless Swift CLI binary (`vibelight-broker`) that accepts Claude Code hook events over local HTTP, runs the 7-state state machine with multi-session arbitration, and drives a Home Assistant light. End-to-end manually testable via `curl`.

**Architecture:** Swift Package Manager package with three targets — `VibeBrokerCore` (pure logic: state machine, session store, arbiter, config), `VibeBrokerNet` (Network.framework I/O: HTTP listener, HA REST client, light drivers), and the `vibelight-broker` executable. Pure-logic layers are unit-tested without I/O. Network layers use `URLProtocol` stubs and real listener on ephemeral ports for integration tests. Concurrency via Swift actors.

**Tech Stack:** Swift 5.9+, SwiftPM, macOS 13+, Foundation, Network.framework, XCTest. Zero third-party dependencies.

**Scope (P1 only):**
- State machine + transitions (7 states)
- SessionStore + TTL
- Arbiter (priority-based)
- HA REST client
- `BrokerEmulatedDriver` only (Scene pack driver is P3)
- HTTP listener with 5 endpoints (`/event`, `/state`, `/test`, `/reload`, `/health`)
- CLI executable + config file
- Hook shell script

**Out of scope (deferred to P2/P3):**
- Any UI (menubar, onboarding, settings)
- HA discovery (mDNS)
- HomeReachability network detection
- Scene pack driver + installer
- Pause feature
- Persistent logging beyond `print()`
- Hook installer (P3)

---

## File Structure

```
VibeLight/
├── Package.swift
├── Sources/
│   ├── VibeBrokerCore/
│   │   ├── State.swift              # enum State + priority/color/effect metadata
│   │   ├── Event.swift              # HookEvent struct
│   │   ├── Transition.swift         # pure function: (state, event) -> nextState
│   │   ├── SessionStore.swift       # actor: per-session state + TTL
│   │   ├── Arbiter.swift            # pure: pick effective_state from sessions
│   │   ├── Config.swift             # JSON config loader
│   │   └── Logger.swift             # thin wrapper around os.Logger
│   ├── VibeBrokerNet/
│   │   ├── HAClient.swift           # REST calls to Home Assistant
│   │   ├── LightDriver.swift        # protocol
│   │   ├── BrokerEmulatedDriver.swift  # effect loops (solid/breathe/blink)
│   │   ├── HTTPListener.swift       # NWListener-based local server
│   │   ├── HTTPRequest.swift        # minimal HTTP parser
│   │   └── EventRouter.swift        # /event, /state, /test, /reload, /health
│   └── vibelight-broker/
│       └── main.swift               # CLI entry: load config, start listener, signal handling
├── Tests/
│   ├── VibeBrokerCoreTests/
│   │   ├── StateTests.swift
│   │   ├── TransitionTests.swift
│   │   ├── SessionStoreTests.swift
│   │   ├── ArbiterTests.swift
│   │   └── ConfigTests.swift
│   └── VibeBrokerNetTests/
│       ├── HAClientTests.swift
│       ├── BrokerEmulatedDriverTests.swift
│       ├── HTTPListenerTests.swift
│       └── EventRouterTests.swift
└── Resources/
    └── vibelight.sh                  # Claude Code hook script
```

---

## Task Index

| # | Task | Test layer |
|---|---|---|
| 1 | Scaffold SwiftPM package | sanity build |
| 2 | `State` enum + metadata | unit |
| 3 | `HookEvent` model | unit |
| 4 | `Transition.apply` pure function | unit |
| 5 | `SessionStore` actor (insert / update / TTL) | unit |
| 6 | `Arbiter.compute` | unit |
| 7 | `Config` JSON loader | unit |
| 8 | `HAClient` REST calls | unit with URLProtocol stub |
| 9 | `LightDriver` protocol + state effect mapping | unit |
| 10 | `BrokerEmulatedDriver` — solid | unit with mock HAClient |
| 11 | `BrokerEmulatedDriver` — breathe loop | unit with mock HAClient |
| 12 | `BrokerEmulatedDriver` — blink loop + auto-stop | unit with mock HAClient |
| 13 | `BrokerEmulatedDriver` — cancel + transitions | unit |
| 14 | Minimal HTTP request parser | unit |
| 15 | `HTTPListener` accepts connections | integration |
| 16 | `EventRouter` — `/event` | integration |
| 17 | `EventRouter` — `/state` `/test` `/reload` `/health` | integration |
| 18 | CLI executable + signal handling | manual smoke |
| 19 | Hook shell script + manual end-to-end | manual smoke |

---

## Task 1: Scaffold SwiftPM Package

**Files:**
- Create: `Package.swift`
- Create: `Sources/VibeBrokerCore/Placeholder.swift`
- Create: `Sources/VibeBrokerNet/Placeholder.swift`
- Create: `Sources/vibelight-broker/App.swift`
- Create: `Tests/VibeBrokerCoreTests/PlaceholderTests.swift`
- Create: `Tests/VibeBrokerNetTests/PlaceholderTests.swift`
- Create: `.gitignore`

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VibeLight",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "VibeBrokerCore", targets: ["VibeBrokerCore"]),
        .library(name: "VibeBrokerNet", targets: ["VibeBrokerNet"]),
        .executable(name: "vibelight-broker", targets: ["vibelight-broker"]),
    ],
    targets: [
        .target(name: "VibeBrokerCore"),
        .target(name: "VibeBrokerNet", dependencies: ["VibeBrokerCore"]),
        .executableTarget(
            name: "vibelight-broker",
            dependencies: ["VibeBrokerCore", "VibeBrokerNet"]
        ),
        .testTarget(name: "VibeBrokerCoreTests", dependencies: ["VibeBrokerCore"]),
        .testTarget(
            name: "VibeBrokerNetTests",
            dependencies: ["VibeBrokerNet", "VibeBrokerCore"]
        ),
    ]
)
```

- [ ] **Step 2: Create placeholder source files**

`Sources/VibeBrokerCore/Placeholder.swift`:
```swift
public enum VibeBrokerCore {}
```

`Sources/VibeBrokerNet/Placeholder.swift`:
```swift
public enum VibeBrokerNet {}
```

`Sources/vibelight-broker/App.swift`:
```swift
import Foundation

@main
struct App {
    static func main() {
        print("vibelight-broker: stub. Implemented in later tasks.")
    }
}
```

- [ ] **Step 3: Create placeholder test files**

`Tests/VibeBrokerCoreTests/PlaceholderTests.swift`:
```swift
import XCTest
@testable import VibeBrokerCore

final class PlaceholderTests: XCTestCase {
    func testPackageBuilds() {
        XCTAssertNotNil(VibeBrokerCore.self)
    }
}
```

`Tests/VibeBrokerNetTests/PlaceholderTests.swift`:
```swift
import XCTest
@testable import VibeBrokerNet

final class PlaceholderTests: XCTestCase {
    func testPackageBuilds() {
        XCTAssertNotNil(VibeBrokerNet.self)
    }
}
```

- [ ] **Step 4: Create `.gitignore`**

```
.build/
.swiftpm/
*.xcodeproj
DerivedData/
.DS_Store
```

- [ ] **Step 5: Verify build and tests pass**

Run: `swift build`
Expected: builds without errors.

Run: `swift test`
Expected: PASS — `testPackageBuilds` in both test targets.

- [ ] **Step 6: Commit**

```bash
git init
git add Package.swift Sources Tests .gitignore
git commit -m "chore: scaffold SwiftPM package for vibelight-broker"
```

---

## Task 2: `State` enum + metadata

**Files:**
- Create: `Sources/VibeBrokerCore/State.swift`
- Create: `Tests/VibeBrokerCoreTests/StateTests.swift`
- Delete: `Sources/VibeBrokerCore/Placeholder.swift`
- Delete: `Tests/VibeBrokerCoreTests/PlaceholderTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/VibeBrokerCoreTests/StateTests.swift`:
```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VibeBrokerCoreTests.StateTests`
Expected: FAIL — `State` not defined.

- [ ] **Step 3: Implement `State.swift`**

`Sources/VibeBrokerCore/State.swift`:
```swift
import Foundation

public enum State: String, CaseIterable, Sendable {
    case idle
    case done
    case working
    case compacting
    case waitingInput
    case needsAuth
    case error

    public var priority: Int {
        switch self {
        case .idle:         return 0
        case .done:         return 1
        case .working:      return 2
        case .compacting:   return 3
        case .waitingInput: return 4
        case .needsAuth:    return 5
        case .error:        return 6
        }
    }

    public var serializedName: String {
        switch self {
        case .idle:         return "idle"
        case .done:         return "done"
        case .working:      return "working"
        case .compacting:   return "compacting"
        case .waitingInput: return "waiting_input"
        case .needsAuth:    return "needs_auth"
        case .error:        return "error"
        }
    }
}
```

- [ ] **Step 4: Delete placeholder files**

```bash
rm Sources/VibeBrokerCore/Placeholder.swift
rm Tests/VibeBrokerCoreTests/PlaceholderTests.swift
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter VibeBrokerCoreTests.StateTests`
Expected: PASS — all 3 tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeBrokerCore Tests/VibeBrokerCoreTests
git commit -m "feat(core): add State enum with priority and serialized names"
```

---

## Task 3: `HookEvent` model

**Files:**
- Create: `Sources/VibeBrokerCore/Event.swift`
- Create: `Tests/VibeBrokerCoreTests/EventTests.swift`

Claude Code hooks send JSON on stdin to the hook command. The hook script forwards that JSON body verbatim to `POST /event?hook=<name>`. The broker receives the hook name as a query string and parses common fields from the body.

Common payload fields across hooks (per Claude Code docs):
- `session_id`: string
- `transcript_path`: string
- `cwd`: string
- For `PostToolUse`: `tool_response` (object that may contain `is_error: bool` for error detection)
- For `Notification`: `message: string`

- [ ] **Step 1: Write the failing tests**

`Tests/VibeBrokerCoreTests/EventTests.swift`:
```swift
import XCTest
@testable import VibeBrokerCore

final class EventTests: XCTestCase {
    func testParseSessionStart() throws {
        let json = #"{"session_id":"abc","transcript_path":"/tmp/t.json","cwd":"/Users/u/p"}"#
        let event = try HookEvent.parse(hookName: "SessionStart", body: Data(json.utf8))

        XCTAssertEqual(event.hookName, .sessionStart)
        XCTAssertEqual(event.sessionId, "abc")
        XCTAssertEqual(event.cwd, "/Users/u/p")
    }

    func testPostToolUseErrorDetection() throws {
        let json = #"""
        {"session_id":"abc","tool_response":{"is_error":true,"error":"boom"}}
        """#
        let event = try HookEvent.parse(hookName: "PostToolUse", body: Data(json.utf8))

        XCTAssertEqual(event.hookName, .postToolUse)
        XCTAssertTrue(event.toolResponseIsError)
    }

    func testPostToolUseSuccess() throws {
        let json = #"{"session_id":"abc","tool_response":{"output":"ok"}}"#
        let event = try HookEvent.parse(hookName: "PostToolUse", body: Data(json.utf8))

        XCTAssertFalse(event.toolResponseIsError)
    }

    func testNotificationMessage() throws {
        let json = #"{"session_id":"abc","message":"Claude needs your permission to use Bash"}"#
        let event = try HookEvent.parse(hookName: "Notification", body: Data(json.utf8))

        XCTAssertEqual(event.notificationMessage, "Claude needs your permission to use Bash")
    }

    func testUnknownHookNameThrows() {
        XCTAssertThrowsError(try HookEvent.parse(hookName: "BogusHook", body: Data("{}".utf8)))
    }

    func testMissingSessionIdThrows() {
        XCTAssertThrowsError(try HookEvent.parse(hookName: "SessionStart", body: Data("{}".utf8)))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VibeBrokerCoreTests.EventTests`
Expected: FAIL — `HookEvent` not defined.

- [ ] **Step 3: Implement `Event.swift`**

`Sources/VibeBrokerCore/Event.swift`:
```swift
import Foundation

public enum HookName: String, Sendable {
    case sessionStart      = "SessionStart"
    case userPromptSubmit  = "UserPromptSubmit"
    case preToolUse        = "PreToolUse"
    case postToolUse       = "PostToolUse"
    case notification      = "Notification"
    case preCompact        = "PreCompact"
    case stop              = "Stop"
    case sessionEnd        = "SessionEnd"
}

public struct HookEvent: Sendable {
    public let hookName: HookName
    public let sessionId: String
    public let cwd: String?
    public let toolResponseIsError: Bool
    public let notificationMessage: String?

    public enum ParseError: Error {
        case unknownHook(String)
        case missingSessionId
        case invalidJSON
    }

    public static func parse(hookName rawName: String, body: Data) throws -> HookEvent {
        guard let hookName = HookName(rawValue: rawName) else {
            throw ParseError.unknownHook(rawName)
        }

        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                throw ParseError.invalidJSON
            }
            json = parsed
        } catch {
            throw ParseError.invalidJSON
        }

        guard let sessionId = json["session_id"] as? String, !sessionId.isEmpty else {
            throw ParseError.missingSessionId
        }

        let cwd = json["cwd"] as? String

        var isError = false
        if hookName == .postToolUse,
           let resp = json["tool_response"] as? [String: Any],
           let flag = resp["is_error"] as? Bool {
            isError = flag
        }

        var notifMsg: String? = nil
        if hookName == .notification {
            notifMsg = json["message"] as? String
        }

        return HookEvent(
            hookName: hookName,
            sessionId: sessionId,
            cwd: cwd,
            toolResponseIsError: isError,
            notificationMessage: notifMsg
        )
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter VibeBrokerCoreTests.EventTests`
Expected: PASS — all 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeBrokerCore/Event.swift Tests/VibeBrokerCoreTests/EventTests.swift
git commit -m "feat(core): add HookEvent parser for Claude Code hooks"
```

---

## Task 4: `Transition.apply` pure function

**Files:**
- Create: `Sources/VibeBrokerCore/Transition.swift`
- Create: `Tests/VibeBrokerCoreTests/TransitionTests.swift`

Pure function from `(currentState, event) -> nextState`. Matches §4 of the spec.

- [ ] **Step 1: Write the failing tests**

`Tests/VibeBrokerCoreTests/TransitionTests.swift`:
```swift
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
        // §2 design note: compacting is a flag; next any-activity clears it.
        XCTAssertEqual(Transition.apply(from: .compacting, event: event(.userPromptSubmit)), .working)
        XCTAssertEqual(Transition.apply(from: .compacting, event: event(.preToolUse)), .working)
        XCTAssertEqual(Transition.apply(from: .compacting, event: event(.postToolUse)), .working)
        XCTAssertEqual(Transition.apply(from: .compacting, event: event(.stop)), .done)
    }

    func testStopGoesToDone() {
        XCTAssertEqual(Transition.apply(from: .working, event: event(.stop)), .done)
    }

    func testFallbackNotificationGoesToNeedsAuthWhenMessageMissing() {
        // If we cannot parse the message reliably, default to NEEDS_AUTH (spec §4 fallback).
        let e = event(.notification, message: nil)
        XCTAssertEqual(Transition.apply(from: .working, event: e), .needsAuth)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VibeBrokerCoreTests.TransitionTests`
Expected: FAIL — `Transition` not defined.

- [ ] **Step 3: Implement `Transition.swift`**

`Sources/VibeBrokerCore/Transition.swift`:
```swift
import Foundation

public enum Transition {
    public static func apply(from state: State, event: HookEvent) -> State {
        switch event.hookName {
        case .sessionStart:
            return .idle

        case .userPromptSubmit, .preToolUse:
            return .working

        case .postToolUse:
            return event.toolResponseIsError ? .error : .working

        case .notification:
            // Fallback: if message missing, treat as NEEDS_AUTH (more conservative — red).
            guard let msg = event.notificationMessage?.lowercased() else {
                return .needsAuth
            }
            if msg.contains("permission") || msg.contains("approve") {
                return .needsAuth
            }
            return .waitingInput

        case .preCompact:
            return .compacting

        case .stop:
            return .done

        case .sessionEnd:
            // Session removal handled at SessionStore level; state irrelevant.
            return .idle
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter VibeBrokerCoreTests.TransitionTests`
Expected: PASS — all tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeBrokerCore/Transition.swift Tests/VibeBrokerCoreTests/TransitionTests.swift
git commit -m "feat(core): add Transition.apply pure state machine"
```

---

## Task 5: `SessionStore` actor

**Files:**
- Create: `Sources/VibeBrokerCore/SessionStore.swift`
- Create: `Tests/VibeBrokerCoreTests/SessionStoreTests.swift`

Actor wrapping `[SessionID: SessionRecord]`. Responsibilities: register on `SessionStart`, apply transitions on events, remove on `SessionEnd`, prune sessions idle > TTL.

- [ ] **Step 1: Write the failing tests**

`Tests/VibeBrokerCoreTests/SessionStoreTests.swift`:
```swift
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
        // Hook events may arrive before SessionStart on cold-start. Auto-register.
        let store = SessionStore(ttlSeconds: 300, now: { Date(timeIntervalSince1970: 0) })
        await store.handle(event(.userPromptSubmit, sessionId: "s1"))

        let all = await store.snapshot()
        XCTAssertEqual(all["s1"]?.state, .working)
    }

    func testTTLPrunesIdleSessions() async {
        var clock = Date(timeIntervalSince1970: 0)
        let store = SessionStore(ttlSeconds: 60, now: { clock })

        await store.handle(event(.sessionStart, sessionId: "s1"))
        clock = Date(timeIntervalSince1970: 120) // advance past TTL
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VibeBrokerCoreTests.SessionStoreTests`
Expected: FAIL — `SessionStore` not defined.

- [ ] **Step 3: Implement `SessionStore.swift`**

`Sources/VibeBrokerCore/SessionStore.swift`:
```swift
import Foundation

public struct SessionRecord: Sendable, Equatable {
    public let id: String
    public var state: State
    public var since: Date
    public var lastEventAt: Date
    public var cwd: String?
}

public actor SessionStore {
    private var sessions: [String: SessionRecord] = [:]
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date

    public init(ttlSeconds: TimeInterval, now: @escaping @Sendable () -> Date = { Date() }) {
        self.ttl = ttlSeconds
        self.now = now
    }

    public func handle(_ event: HookEvent) {
        let timestamp = now()

        if event.hookName == .sessionEnd {
            sessions.removeValue(forKey: event.sessionId)
            return
        }

        if var existing = sessions[event.sessionId] {
            let next = Transition.apply(from: existing.state, event: event)
            if next != existing.state {
                existing.state = next
                existing.since = timestamp
            }
            existing.lastEventAt = timestamp
            if let cwd = event.cwd { existing.cwd = cwd }
            sessions[event.sessionId] = existing
        } else {
            let initialState = Transition.apply(from: .idle, event: event)
            sessions[event.sessionId] = SessionRecord(
                id: event.sessionId, state: initialState,
                since: timestamp, lastEventAt: timestamp, cwd: event.cwd
            )
        }
    }

    @discardableResult
    public func pruneExpired() -> Int {
        let cutoff = now().addingTimeInterval(-ttl)
        let expired = sessions.filter { $0.value.lastEventAt < cutoff }.map(\.key)
        for id in expired { sessions.removeValue(forKey: id) }
        return expired.count
    }

    public func snapshot() -> [String: SessionRecord] {
        sessions
    }

    /// For internal callers needing to override state without an event (used by error auto-clear timer).
    public func setState(_ state: State, for sessionId: String) {
        guard var existing = sessions[sessionId] else { return }
        existing.state = state
        existing.since = now()
        existing.lastEventAt = now()
        sessions[sessionId] = existing
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter VibeBrokerCoreTests.SessionStoreTests`
Expected: PASS — all 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeBrokerCore/SessionStore.swift Tests/VibeBrokerCoreTests/SessionStoreTests.swift
git commit -m "feat(core): add SessionStore actor with TTL pruning"
```

---

## Task 6: `Arbiter.compute`

**Files:**
- Create: `Sources/VibeBrokerCore/Arbiter.swift`
- Create: `Tests/VibeBrokerCoreTests/ArbiterTests.swift`

Pure function: given session records, return effective state. Highest priority wins; ties broken by most recent `since`.

- [ ] **Step 1: Write the failing tests**

`Tests/VibeBrokerCoreTests/ArbiterTests.swift`:
```swift
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
        // Both same priority; effective is still working. We only test it doesn't crash and picks ONE.
        XCTAssertEqual(Arbiter.compute(store), .working)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VibeBrokerCoreTests.ArbiterTests`
Expected: FAIL — `Arbiter` not defined.

- [ ] **Step 3: Implement `Arbiter.swift`**

`Sources/VibeBrokerCore/Arbiter.swift`:
```swift
import Foundation

public enum Arbiter {
    public static func compute(_ sessions: [String: SessionRecord]) -> State {
        guard !sessions.isEmpty else { return .idle }
        let sorted = sessions.values.sorted { a, b in
            if a.state.priority != b.state.priority {
                return a.state.priority > b.state.priority
            }
            return a.since > b.since
        }
        return sorted.first?.state ?? .idle
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter VibeBrokerCoreTests.ArbiterTests`
Expected: PASS — all 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeBrokerCore/Arbiter.swift Tests/VibeBrokerCoreTests/ArbiterTests.swift
git commit -m "feat(core): add Arbiter for multi-session effective state"
```

---

## Task 7: `Config` JSON loader

**Files:**
- Create: `Sources/VibeBrokerCore/Config.swift`
- Create: `Tests/VibeBrokerCoreTests/ConfigTests.swift`

Config in JSON (not TOML — avoids extra dependency). Schema mirrors spec §6 (broker port, HA URL/token/entity, behavior, colors).

- [ ] **Step 1: Write the failing tests**

`Tests/VibeBrokerCoreTests/ConfigTests.swift`:
```swift
import XCTest
@testable import VibeBrokerCore

final class ConfigTests: XCTestCase {
    private let validJSON = #"""
    {
      "broker": { "port": 17345 },
      "homeAssistant": {
        "url": "http://homeassistant.local:8123",
        "token": "abc123",
        "lightEntity": "light.desk_strip"
      },
      "behavior": {
        "sessionTtlSeconds": 300,
        "errorAutoClearSeconds": 5,
        "doneBlinkSeconds": 2,
        "waitingInputBlinkSeconds": 3,
        "debounceMillis": 100
      },
      "colors": {
        "idle":         { "rgb": [80, 30, 120], "brightness": 80,  "effect": "solid" },
        "working":      { "rgb": [40, 120, 255], "brightness": 200, "effect": "breathe" },
        "compacting":   { "rgb": [240, 220, 60], "brightness": 200, "effect": "breathe" },
        "waiting_input":{ "rgb": [255, 140, 30], "brightness": 220, "effect": "blink_then_solid" },
        "needs_auth":   { "rgb": [255, 30, 30], "brightness": 230, "effect": "solid" },
        "error":        { "rgb": [255, 30, 30], "brightness": 230, "effect": "blink" },
        "done":         { "rgb": [80, 30, 120], "brightness": 200, "effect": "blink" }
      }
    }
    """#

    func testParseValid() throws {
        let cfg = try Config.parse(Data(validJSON.utf8))

        XCTAssertEqual(cfg.broker.port, 17345)
        XCTAssertEqual(cfg.homeAssistant.url.absoluteString, "http://homeassistant.local:8123")
        XCTAssertEqual(cfg.homeAssistant.token, "abc123")
        XCTAssertEqual(cfg.homeAssistant.lightEntity, "light.desk_strip")
        XCTAssertEqual(cfg.behavior.sessionTtlSeconds, 300)
        XCTAssertEqual(cfg.colors[.working]?.rgb, [40, 120, 255])
        XCTAssertEqual(cfg.colors[.working]?.effect, .breathe)
    }

    func testMissingRequiredFieldThrows() {
        let badJSON = #"{"broker":{"port":17345}}"#
        XCTAssertThrowsError(try Config.parse(Data(badJSON.utf8)))
    }

    func testEffectParsing() throws {
        let cfg = try Config.parse(Data(validJSON.utf8))
        XCTAssertEqual(cfg.colors[.error]?.effect, .blink)
        XCTAssertEqual(cfg.colors[.waitingInput]?.effect, .blinkThenSolid)
        XCTAssertEqual(cfg.colors[.idle]?.effect, .solid)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VibeBrokerCoreTests.ConfigTests`
Expected: FAIL — `Config` not defined.

- [ ] **Step 3: Implement `Config.swift`**

`Sources/VibeBrokerCore/Config.swift`:
```swift
import Foundation

public enum Effect: String, Codable, Sendable {
    case solid
    case breathe
    case blink
    case blinkThenSolid = "blink_then_solid"
}

public struct ColorConfig: Codable, Sendable, Equatable {
    public let rgb: [Int]            // [r, g, b], 0-255
    public let brightness: Int       // 0-255
    public let effect: Effect
}

public struct BrokerConfig: Codable, Sendable {
    public let port: UInt16
}

public struct HAConfig: Codable, Sendable {
    public let url: URL
    public let token: String
    public let lightEntity: String
}

public struct BehaviorConfig: Codable, Sendable {
    public let sessionTtlSeconds: TimeInterval
    public let errorAutoClearSeconds: TimeInterval
    public let doneBlinkSeconds: TimeInterval
    public let waitingInputBlinkSeconds: TimeInterval
    public let debounceMillis: Int
}

public struct Config: Sendable {
    public let broker: BrokerConfig
    public let homeAssistant: HAConfig
    public let behavior: BehaviorConfig
    public let colors: [State: ColorConfig]

    private struct Raw: Codable {
        let broker: BrokerConfig
        let homeAssistant: HAConfig
        let behavior: BehaviorConfig
        let colors: [String: ColorConfig]
    }

    public static func parse(_ data: Data) throws -> Config {
        let raw = try JSONDecoder().decode(Raw.self, from: data)

        var byState: [State: ColorConfig] = [:]
        for state in State.allCases {
            guard let color = raw.colors[state.serializedName] else {
                throw ParseError.missingColor(state.serializedName)
            }
            byState[state] = color
        }

        return Config(
            broker: raw.broker,
            homeAssistant: raw.homeAssistant,
            behavior: raw.behavior,
            colors: byState
        )
    }

    public enum ParseError: Error, Equatable {
        case missingColor(String)
    }

    public static func loadFromDisk(_ url: URL) throws -> Config {
        try parse(try Data(contentsOf: url))
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter VibeBrokerCoreTests.ConfigTests`
Expected: PASS — all 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeBrokerCore/Config.swift Tests/VibeBrokerCoreTests/ConfigTests.swift
git commit -m "feat(core): add JSON config loader"
```

---

## Task 8: `HAClient` REST calls

**Files:**
- Create: `Sources/VibeBrokerNet/HAClient.swift`
- Create: `Tests/VibeBrokerNetTests/HAClientTests.swift`

Thin async client for HA REST API. Two operations needed in P1: `callService(domain, service, data)` and `getApiStatus()` (for reachability check, used in P3 — we add it now for testing parity).

Test technique: register a `URLProtocol` subclass on a custom `URLSession` to intercept requests and return canned responses.

- [ ] **Step 1: Write the failing tests**

`Tests/VibeBrokerNetTests/HAClientTests.swift`:
```swift
import XCTest
@testable import VibeBrokerNet
@testable import VibeBrokerCore

// MARK: - URLProtocol stub

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "no handler", code: 0))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class HAClientTests: XCTestCase {
    private func makeClient() -> HAClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: cfg)
        return HAClient(
            baseURL: URL(string: "http://test.local:8123")!,
            token: "T0KEN",
            session: session
        )
    }

    func testCallServiceSendsPOST() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.handler = { req in
            capturedRequest = req
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data("[]".utf8))
        }

        let client = makeClient()
        try await client.callService(
            domain: "light",
            service: "turn_on",
            data: ["entity_id": "light.desk", "rgb_color": [255, 0, 0]]
        )

        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.url?.path, "/api/services/light/turn_on")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer T0KEN")

        let bodyData = capturedRequest!.httpBodyStreamData ?? capturedRequest!.httpBody!
        let body = try JSONSerialization.jsonObject(with: bodyData) as! [String: Any]
        XCTAssertEqual(body["entity_id"] as? String, "light.desk")
    }

    func testCallServiceThrowsOn4xx() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data("{}".utf8))
        }
        let client = makeClient()
        do {
            try await client.callService(domain: "light", service: "turn_on", data: [:])
            XCTFail("expected throw")
        } catch HAClient.Error.unauthorized {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testGetApiStatusReturnsTrueOn200() async throws {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data("{}".utf8))
        }
        let client = makeClient()
        let ok = try await client.getApiStatus()
        XCTAssertTrue(ok)
    }
}

extension URLRequest {
    /// URLProtocol receives body via httpBodyStream for streamed bodies; drain it for inspection.
    var httpBodyStreamData: Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buf.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buf, maxLength: 4096)
            if read <= 0 { break }
            data.append(buf, count: read)
        }
        return data
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VibeBrokerNetTests.HAClientTests`
Expected: FAIL — `HAClient` not defined.

- [ ] **Step 3: Implement `HAClient.swift`**

`Sources/VibeBrokerNet/HAClient.swift`:
```swift
import Foundation

public final class HAClient: @unchecked Sendable {
    public enum Error: Swift.Error, Equatable {
        case unauthorized
        case server(Int)
        case transport(String)
        case encoding
    }

    private let baseURL: URL
    private let token: String
    private let session: URLSession

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    public func callService(domain: String, service: String,
                            data: [String: Any]) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/services/\(domain)/\(service)"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 2.0
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: data)
        } catch {
            throw Error.encoding
        }

        let (_, response) = try await sendRequest(request)
        try assertOK(response)
    }

    public func getApiStatus() async throws -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 0.5

        let (_, response) = try await sendRequest(request)
        guard let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    private func sendRequest(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: req)
        } catch {
            throw Error.transport(String(describing: error))
        }
    }

    private func assertOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw Error.server(-1)
        }
        if http.statusCode == 401 { throw Error.unauthorized }
        if !(200..<300).contains(http.statusCode) {
            throw Error.server(http.statusCode)
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter VibeBrokerNetTests.HAClientTests`
Expected: PASS — all 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeBrokerNet/HAClient.swift Tests/VibeBrokerNetTests/HAClientTests.swift
git commit -m "feat(net): add HAClient with URLProtocol-tested REST calls"
```

---

## Task 9: `LightDriver` protocol + helpers

**Files:**
- Create: `Sources/VibeBrokerNet/LightDriver.swift`
- (no separate test file; protocol-only)

Protocol with two methods: `render(state)` and `cancel()`. Define a shared payload helper that converts a `ColorConfig` into a `light.turn_on` data dictionary.

- [ ] **Step 1: Implement `LightDriver.swift`**

`Sources/VibeBrokerNet/LightDriver.swift`:
```swift
import Foundation
import VibeBrokerCore

public protocol LightDriver: Sendable {
    /// Render the effective state on the light. Cancels any in-flight effect.
    func render(_ state: State) async
    /// Cancel any in-flight effect loop without changing the light.
    func cancel() async
}

public enum LightPayload {
    /// Build a `light.turn_on` service data payload from a color config.
    /// `transition` is in seconds (HA semantics: server interpolates over this duration).
    public static func turnOn(entityId: String, color: ColorConfig,
                              transition: Double, brightnessOverride: Int? = nil) -> [String: Any] {
        [
            "entity_id": entityId,
            "rgb_color": color.rgb,
            "brightness": brightnessOverride ?? color.brightness,
            "transition": transition,
        ]
    }

    public static func turnOff(entityId: String, transition: Double = 0) -> [String: Any] {
        [
            "entity_id": entityId,
            "transition": transition,
        ]
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: builds.

- [ ] **Step 3: Commit**

```bash
git add Sources/VibeBrokerNet/LightDriver.swift
git commit -m "feat(net): add LightDriver protocol and turn-on payload helper"
```

---

## Task 10: `BrokerEmulatedDriver` — solid effect

**Files:**
- Create: `Sources/VibeBrokerNet/BrokerEmulatedDriver.swift`
- Create: `Tests/VibeBrokerNetTests/BrokerEmulatedDriverTests.swift`

`BrokerEmulatedDriver` runs the effect loop inside a `Task`. Solid is the simplest: one `callService(light.turn_on, ...)`.

Testing approach: a `SpyHAClient` (extends `HAClient` via protocol indirection? — simpler: wrap `HAClient`'s only consumer with a protocol). Let me introduce a `LightServiceCaller` protocol.

- [ ] **Step 1: Introduce a `LightServiceCaller` protocol in HAClient.swift**

Modify `Sources/VibeBrokerNet/HAClient.swift` — add at the top of the file (above `HAClient` class):

```swift
public protocol LightServiceCaller: Sendable {
    func callService(domain: String, service: String, data: [String: Any]) async throws
}
```

Make `HAClient` conform:
```swift
extension HAClient: LightServiceCaller {}
```

Add this `extension` at the end of `HAClient.swift`.

- [ ] **Step 2: Write the failing tests**

`Tests/VibeBrokerNetTests/BrokerEmulatedDriverTests.swift`:
```swift
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
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter VibeBrokerNetTests.BrokerEmulatedDriverSolidTests`
Expected: FAIL — `BrokerEmulatedDriver` not defined.

- [ ] **Step 4: Implement `BrokerEmulatedDriver.swift` (solid only for now)**

`Sources/VibeBrokerNet/BrokerEmulatedDriver.swift`:
```swift
import Foundation
import VibeBrokerCore

public actor BrokerEmulatedDriver: LightDriver {
    private let client: LightServiceCaller
    private let config: Config
    private var currentTask: Task<Void, Never>?

    public init(client: LightServiceCaller, config: Config) {
        self.client = client
        self.config = config
    }

    public func render(_ state: State) async {
        await cancel()
        let color = config.colors[state]!  // config schema guarantees presence
        let entityId = config.homeAssistant.lightEntity

        switch color.effect {
        case .solid:
            currentTask = Task { [client] in
                try? await client.callService(
                    domain: "light", service: "turn_on",
                    data: LightPayload.turnOn(entityId: entityId, color: color, transition: 0.3)
                )
            }
        case .breathe, .blink, .blinkThenSolid:
            // Implemented in tasks 11, 12.
            break
        }
    }

    public func cancel() async {
        currentTask?.cancel()
        currentTask = nil
    }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter VibeBrokerNetTests.BrokerEmulatedDriverSolidTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeBrokerNet Tests/VibeBrokerNetTests/BrokerEmulatedDriverTests.swift
git commit -m "feat(net): add BrokerEmulatedDriver with solid effect"
```

---

## Task 11: `BrokerEmulatedDriver` — breathe loop

Strategy: every 1 s, alternate between min (30% brightness) and max (configured brightness), with `transition: 1.0` so HA interpolates server-side. Total: ~1 call/s.

**Files:**
- Modify: `Sources/VibeBrokerNet/BrokerEmulatedDriver.swift`
- Modify: `Tests/VibeBrokerNetTests/BrokerEmulatedDriverTests.swift`

- [ ] **Step 1: Add failing test**

Append to `BrokerEmulatedDriverTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VibeBrokerNetTests.BrokerEmulatedDriverBreatheTests`
Expected: FAIL — `breathe` case currently does nothing.

- [ ] **Step 3: Implement breathe loop**

Replace the `.breathe` case body in `BrokerEmulatedDriver.swift`:

```swift
case .breathe:
    currentTask = Task { [client, color, entityId] in
        var high = true
        let highBrightness = color.brightness
        let lowBrightness = max(20, color.brightness / 3)
        while !Task.isCancelled {
            try? await client.callService(
                domain: "light", service: "turn_on",
                data: LightPayload.turnOn(
                    entityId: entityId, color: color, transition: 1.0,
                    brightnessOverride: high ? highBrightness : lowBrightness
                )
            )
            high.toggle()
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 s
        }
    }
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter VibeBrokerNetTests.BrokerEmulatedDriverBreatheTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeBrokerNet/BrokerEmulatedDriver.swift Tests/VibeBrokerNetTests/BrokerEmulatedDriverTests.swift
git commit -m "feat(net): add breathe effect loop to BrokerEmulatedDriver"
```

---

## Task 12: `BrokerEmulatedDriver` — blink + blink_then_solid

Blink: alternate on/off every 500 ms, `transition: 0`. ERROR uses `effect: .blink`. For ERROR the spec says "5 s then auto-clear" — auto-clear is at the SessionStore level (Task 18 wires it). The driver just blinks forever until cancelled.

`blink_then_solid`: blink for `waitingInputBlinkSeconds`, then settle to solid.

**Files:**
- Modify: `Sources/VibeBrokerNet/BrokerEmulatedDriver.swift`
- Modify: `Tests/VibeBrokerNetTests/BrokerEmulatedDriverTests.swift`

- [ ] **Step 1: Add failing tests**

Append to `BrokerEmulatedDriverTests.swift`:

```swift
final class BrokerEmulatedDriverBlinkTests: XCTestCase {
    func testBlinkAlternatesOnOff() async {
        let cfg = BrokerEmulatedDriverSolidTests().makeConfigForBreathe()
        let spy = SpyHAClient()
        let driver = BrokerEmulatedDriver(client: spy, config: cfg)

        await driver.render(.error)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await driver.cancel()

        // Blink at 2 Hz → ~3 turn_on/turn_off pairs in 1.5 s
        let services = spy.calls.map { $0.service }
        XCTAssertTrue(services.contains("turn_on"))
        XCTAssertTrue(services.contains("turn_off"))
    }

    func testBlinkThenSolidEndsWithSolid() async {
        var cfg = BrokerEmulatedDriverSolidTests().makeConfigForBreathe()
        // Override waitingInput to blinkThenSolid for this test.
        let blinkColor = ColorConfig(rgb: [255, 140, 30], brightness: 220, effect: .blinkThenSolid)
        var colors = cfg.colors
        colors[.waitingInput] = blinkColor
        cfg = Config(
            broker: cfg.broker, homeAssistant: cfg.homeAssistant,
            behavior: BehaviorConfig(
                sessionTtlSeconds: cfg.behavior.sessionTtlSeconds,
                errorAutoClearSeconds: cfg.behavior.errorAutoClearSeconds,
                doneBlinkSeconds: cfg.behavior.doneBlinkSeconds,
                waitingInputBlinkSeconds: 1.0,  // shorten for test
                debounceMillis: cfg.behavior.debounceMillis
            ),
            colors: colors
        )
        let spy = SpyHAClient()
        let driver = BrokerEmulatedDriver(client: spy, config: cfg)

        await driver.render(.waitingInput)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await driver.cancel()

        // After 1 s blink, last call should be a solid turn_on.
        XCTAssertEqual(spy.calls.last?.service, "turn_on")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VibeBrokerNetTests.BrokerEmulatedDriverBlinkTests`
Expected: FAIL — `blink` and `blinkThenSolid` cases currently do nothing.

- [ ] **Step 3: Implement blink + blinkThenSolid cases**

Replace `.blink`/`.blinkThenSolid` cases:

```swift
case .blink:
    currentTask = Task { [client, color, entityId] in
        var on = true
        while !Task.isCancelled {
            if on {
                try? await client.callService(
                    domain: "light", service: "turn_on",
                    data: LightPayload.turnOn(entityId: entityId, color: color, transition: 0)
                )
            } else {
                try? await client.callService(
                    domain: "light", service: "turn_off",
                    data: LightPayload.turnOff(entityId: entityId, transition: 0)
                )
            }
            on.toggle()
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 s -> 1 Hz blink
        }
    }

case .blinkThenSolid:
    let blinkSeconds = config.behavior.waitingInputBlinkSeconds
    currentTask = Task { [client, color, entityId] in
        let deadline = Date().addingTimeInterval(blinkSeconds)
        var on = true
        while !Task.isCancelled, Date() < deadline {
            if on {
                try? await client.callService(
                    domain: "light", service: "turn_on",
                    data: LightPayload.turnOn(entityId: entityId, color: color, transition: 0)
                )
            } else {
                try? await client.callService(
                    domain: "light", service: "turn_off",
                    data: LightPayload.turnOff(entityId: entityId, transition: 0)
                )
            }
            on.toggle()
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        // Settle to solid.
        if !Task.isCancelled {
            try? await client.callService(
                domain: "light", service: "turn_on",
                data: LightPayload.turnOn(entityId: entityId, color: color, transition: 0.3)
            )
        }
    }
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter VibeBrokerNetTests.BrokerEmulatedDriverBlinkTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeBrokerNet/BrokerEmulatedDriver.swift Tests/VibeBrokerNetTests/BrokerEmulatedDriverTests.swift
git commit -m "feat(net): add blink and blink_then_solid effects"
```

---

## Task 13: `BrokerEmulatedDriver` — cancel between transitions

When `render(newState)` is called while a previous effect is running, the previous `Task` must cancel cleanly before the new one starts.

**Files:**
- Modify: `Tests/VibeBrokerNetTests/BrokerEmulatedDriverTests.swift`
- (no change needed to `BrokerEmulatedDriver.swift` if Task 10's `await cancel()` is correct — verify with test)

- [ ] **Step 1: Add failing test**

Append to `BrokerEmulatedDriverTests.swift`:

```swift
final class BrokerEmulatedDriverCancellationTests: XCTestCase {
    func testRenderCancelsPreviousEffect() async {
        let cfg = BrokerEmulatedDriverSolidTests().makeConfigForBreathe()
        let spy = SpyHAClient()
        let driver = BrokerEmulatedDriver(client: spy, config: cfg)

        // Start breathe.
        await driver.render(.working)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let countAfterBreathe = spy.calls.count

        // Switch to solid (needsAuth).
        await driver.render(.needsAuth)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let countAfterSwitch = spy.calls.count

        // After switching to a solid effect, only ~1 additional call should appear
        // (instead of continuing to add ~1/s for breathe).
        XCTAssertLessThanOrEqual(countAfterSwitch - countAfterBreathe, 3,
            "previous breathe effect should have been cancelled")

        await driver.cancel()
    }
}
```

- [ ] **Step 2: Run test**

Run: `swift test --filter VibeBrokerNetTests.BrokerEmulatedDriverCancellationTests`
Expected: PASS if Task 10's cancel logic is correct. If it fails, the issue is that `await cancel()` doesn't await the task. Fix by adding `_ = await currentTask?.value` after cancel — but `Task<Void, Never>.value` doesn't suspend on cancellation, so the simpler fix is just to set `currentTask = nil` after calling `cancel()` (which is already in Task 10's code).

If the test fails, inspect by adding `print` to the breathe loop and confirm `Task.isCancelled` becomes true.

- [ ] **Step 3: Commit**

```bash
git add Tests/VibeBrokerNetTests/BrokerEmulatedDriverTests.swift
git commit -m "test(net): verify driver cancels previous effect on transition"
```

---

## Task 14: Minimal HTTP request parser

**Files:**
- Create: `Sources/VibeBrokerNet/HTTPRequest.swift`
- Create: `Tests/VibeBrokerNetTests/HTTPRequestTests.swift`

We parse just enough HTTP to handle our 5 endpoints: method, path, query string, headers (for content-length), body. No keep-alive, no chunked. One request per connection.

- [ ] **Step 1: Write the failing tests**

`Tests/VibeBrokerNetTests/HTTPRequestTests.swift`:
```swift
import XCTest
@testable import VibeBrokerNet

final class HTTPRequestTests: XCTestCase {
    func testParseSimpleGET() throws {
        let raw = "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let req = try HTTPRequest.parse(Data(raw.utf8))
        XCTAssertEqual(req.method, "GET")
        XCTAssertEqual(req.path, "/health")
        XCTAssertTrue(req.query.isEmpty)
        XCTAssertTrue(req.body.isEmpty)
    }

    func testParseQueryString() throws {
        let raw = "POST /event?hook=PreToolUse&x=1 HTTP/1.1\r\nContent-Length: 0\r\n\r\n"
        let req = try HTTPRequest.parse(Data(raw.utf8))
        XCTAssertEqual(req.path, "/event")
        XCTAssertEqual(req.query["hook"], "PreToolUse")
        XCTAssertEqual(req.query["x"], "1")
    }

    func testParsePostBody() throws {
        let body = #"{"session_id":"s1"}"#
        let raw = "POST /event HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let req = try HTTPRequest.parse(Data(raw.utf8))
        XCTAssertEqual(String(data: req.body, encoding: .utf8), body)
    }

    func testMalformedThrows() {
        let raw = "garbage"
        XCTAssertThrowsError(try HTTPRequest.parse(Data(raw.utf8)))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VibeBrokerNetTests.HTTPRequestTests`
Expected: FAIL — `HTTPRequest` not defined.

- [ ] **Step 3: Implement `HTTPRequest.swift`**

`Sources/VibeBrokerNet/HTTPRequest.swift`:
```swift
import Foundation

public struct HTTPRequest: Sendable {
    public let method: String
    public let path: String
    public let query: [String: String]
    public let headers: [String: String]
    public let body: Data

    public enum ParseError: Error { case malformed }

    public static func parse(_ data: Data) throws -> HTTPRequest {
        // Find header / body boundary: "\r\n\r\n".
        guard let separatorRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            throw ParseError.malformed
        }
        let headerData = data.subdata(in: 0..<separatorRange.lowerBound)
        let bodyData = data.subdata(in: separatorRange.upperBound..<data.count)

        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw ParseError.malformed
        }
        let lines = headerString.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { throw ParseError.malformed }

        let requestLine = lines[0].components(separatedBy: " ")
        guard requestLine.count >= 2 else { throw ParseError.malformed }
        let method = requestLine[0]
        let rawTarget = requestLine[1]

        let (path, query) = splitPathAndQuery(rawTarget)

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        return HTTPRequest(method: method, path: path, query: query, headers: headers, body: bodyData)
    }

    private static func splitPathAndQuery(_ target: String) -> (String, [String: String]) {
        guard let qmark = target.firstIndex(of: "?") else {
            return (target, [:])
        }
        let path = String(target[..<qmark])
        let queryString = String(target[target.index(after: qmark)...])
        var query: [String: String] = [:]
        for pair in queryString.components(separatedBy: "&") {
            let kv = pair.components(separatedBy: "=")
            if kv.count == 2 {
                query[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
            } else if kv.count == 1, !kv[0].isEmpty {
                query[kv[0]] = ""
            }
        }
        return (path, query)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter VibeBrokerNetTests.HTTPRequestTests`
Expected: PASS — all 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeBrokerNet/HTTPRequest.swift Tests/VibeBrokerNetTests/HTTPRequestTests.swift
git commit -m "feat(net): add minimal HTTP request parser"
```

---

## Task 15: `HTTPListener` accepts connections

**Files:**
- Create: `Sources/VibeBrokerNet/HTTPListener.swift`
- Create: `Tests/VibeBrokerNetTests/HTTPListenerTests.swift`

`HTTPListener` wraps `NWListener` on `127.0.0.1`. Caller supplies a handler closure `(HTTPRequest) async -> HTTPResponse`. Single-connection-per-request, no keep-alive.

- [ ] **Step 1: Write the failing tests**

`Tests/VibeBrokerNetTests/HTTPListenerTests.swift`:
```swift
import XCTest
@testable import VibeBrokerNet

final class HTTPListenerTests: XCTestCase {
    func testListenerRoutesRequestToHandler() async throws {
        let listener = HTTPListener(port: 0) { request in
            HTTPResponse(status: 200, body: Data("hi from \(request.path)".utf8))
        }
        try await listener.start()
        defer { Task { await listener.stop() } }

        let port = await listener.boundPort()
        let url = URL(string: "http://127.0.0.1:\(port)/health")!

        let (data, response) = try await URLSession.shared.data(from: url)
        let http = response as! HTTPURLResponse
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), "hi from /health")
    }

    func testListenerHandlesPostBody() async throws {
        var capturedBody: Data?
        let listener = HTTPListener(port: 0) { request in
            capturedBody = request.body
            return HTTPResponse(status: 204, body: Data())
        }
        try await listener.start()
        defer { Task { await listener.stop() } }

        let port = await listener.boundPort()
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/event")!)
        req.httpMethod = "POST"
        req.httpBody = Data("{\"hello\":1}".utf8)

        let (_, response) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((response as! HTTPURLResponse).statusCode, 204)
        XCTAssertEqual(String(data: capturedBody ?? Data(), encoding: .utf8), #"{"hello":1}"#)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VibeBrokerNetTests.HTTPListenerTests`
Expected: FAIL — `HTTPListener` not defined.

- [ ] **Step 3: Implement `HTTPListener.swift`**

`Sources/VibeBrokerNet/HTTPListener.swift`:
```swift
import Foundation
import Network

public struct HTTPResponse: Sendable {
    public let status: Int
    public let body: Data
    public let contentType: String

    public init(status: Int, body: Data, contentType: String = "application/json") {
        self.status = status
        self.body = body
        self.contentType = contentType
    }
}

public actor HTTPListener {
    public typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    private let requestedPort: NWEndpoint.Port
    private let handler: Handler
    private var listener: NWListener?

    public init(port: UInt16, handler: @escaping Handler) {
        self.requestedPort = NWEndpoint.Port(rawValue: port == 0 ? 0 : port) ?? .any
        self.handler = handler
    }

    public func start() async throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Bind to loopback only.
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"), port: requestedPort
        )

        let listener = try NWListener(using: params, on: requestedPort)
        listener.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            Task { await self.handle(conn) }
        }

        let stateStream = AsyncStream<NWListener.State> { cont in
            listener.stateUpdateHandler = { cont.yield($0) }
            listener.start(queue: .global())
        }
        for await s in stateStream {
            switch s {
            case .ready: self.listener = listener; return
            case .failed(let e): throw e
            default: continue
            }
        }
    }

    public func boundPort() async -> UInt16 {
        listener?.port?.rawValue ?? 0
    }

    public func stop() async {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ conn: NWConnection) async {
        conn.start(queue: .global())
        do {
            let raw = try await readUntilHeadersAndBody(conn)
            let request = try HTTPRequest.parse(raw)
            let response = await handler(request)
            try await send(response, on: conn)
        } catch {
            try? await send(HTTPResponse(status: 400, body: Data()), on: conn)
        }
        conn.cancel()
    }

    private func readUntilHeadersAndBody(_ conn: NWConnection) async throws -> Data {
        var buffer = Data()
        while true {
            let chunk = try await receiveOnce(conn)
            buffer.append(chunk)
            // Check for header end.
            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                // Have we read the full body?
                let headerString = String(data: buffer.subdata(in: 0..<headerEnd.lowerBound), encoding: .utf8) ?? ""
                let contentLength = parseContentLength(headerString)
                let bodyStart = headerEnd.upperBound
                let bodyReceived = buffer.count - bodyStart
                if bodyReceived >= contentLength {
                    return buffer
                }
            }
            if chunk.isEmpty { return buffer }
        }
    }

    private func parseContentLength(_ headers: String) -> Int {
        for line in headers.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(value) ?? 0
            }
        }
        return 0
    }

    private func receiveOnce(_ conn: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: data ?? Data())
            }
        }
    }

    private func send(_ response: HTTPResponse, on conn: NWConnection) async throws {
        let statusText = HTTPListener.statusText(response.status)
        var head = "HTTP/1.1 \(response.status) \(statusText)\r\n"
        head += "Content-Type: \(response.contentType)\r\n"
        head += "Content-Length: \(response.body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var full = Data(head.utf8)
        full.append(response.body)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: full, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    private static func statusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default:  return "OK"
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter VibeBrokerNetTests.HTTPListenerTests`
Expected: PASS — both tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeBrokerNet/HTTPListener.swift Tests/VibeBrokerNetTests/HTTPListenerTests.swift
git commit -m "feat(net): add NWListener-based HTTP server"
```

---

## Task 16: `EventRouter` — wire `/event` to SessionStore + Driver

**Files:**
- Create: `Sources/VibeBrokerNet/EventRouter.swift`
- Create: `Tests/VibeBrokerNetTests/EventRouterTests.swift`

`EventRouter` holds references to `SessionStore`, `LightDriver`, and `Config`. Dispatches HTTP requests to handlers.

Also implements **ERROR auto-clear timer**: when a session transitions into ERROR, schedule a task to clear it after `errorAutoClearSeconds`. Cancel the timer if any new event arrives for that session.

Also implements **debounce**: state changes within `debounceMillis` produce only the latest driver render.

- [ ] **Step 1: Write the failing tests**

`Tests/VibeBrokerNetTests/EventRouterTests.swift`:
```swift
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

        // Allow render Task to flush.
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
        // Override errorAutoClearSeconds to 0.3s for testing.
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

        // Trigger ERROR via PostToolUse with is_error=true.
        let body = #"{"session_id":"s1","tool_response":{"is_error":true}}"#
        let request = HTTPRequest(
            method: "POST", path: "/event",
            query: ["hook": "PostToolUse"], headers: [:], body: Data(body.utf8)
        )
        _ = await router.handle(request)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(driver.lastRendered, .error)

        // Wait past auto-clear deadline.
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VibeBrokerNetTests.EventRouterTests`
Expected: FAIL — `EventRouter` not defined.

- [ ] **Step 3: Implement `EventRouter.swift`**

`Sources/VibeBrokerNet/EventRouter.swift`:
```swift
import Foundation
import VibeBrokerCore

public actor EventRouter {
    private let store: SessionStore
    private let driver: LightDriver
    private let config: Config

    private var errorClearTasks: [String: Task<Void, Never>] = [:]
    private var debounceTask: Task<Void, Never>?

    public init(store: SessionStore, driver: LightDriver, config: Config) {
        self.store = store
        self.driver = driver
        self.config = config
    }

    public func handle(_ request: HTTPRequest) async -> HTTPResponse {
        switch (request.method, request.path) {
        case ("POST", "/event"):
            return await handleEvent(request)
        case ("GET", "/state"):
            return await handleState()
        case ("POST", "/test"):
            return await handleTest(request)
        case ("POST", "/reload"):
            return HTTPResponse(status: 204, body: Data())
        case ("GET", "/health"):
            return HTTPResponse(status: 200, body: Data("{\"ok\":true}".utf8))
        default:
            return HTTPResponse(status: 404, body: Data())
        }
    }

    private func handleEvent(_ request: HTTPRequest) async -> HTTPResponse {
        guard let hookName = request.query["hook"] else {
            return HTTPResponse(status: 400, body: Data("missing hook".utf8))
        }
        do {
            let event = try HookEvent.parse(hookName: hookName, body: request.body)
            await store.handle(event)

            // Cancel any pending ERROR auto-clear for this session — fresh event invalidates it.
            errorClearTasks[event.sessionId]?.cancel()
            errorClearTasks.removeValue(forKey: event.sessionId)

            await renderEffective()

            // Schedule ERROR auto-clear if needed.
            let snapshot = await store.snapshot()
            if let record = snapshot[event.sessionId], record.state == .error {
                scheduleErrorClear(sessionId: event.sessionId)
            }

            return HTTPResponse(status: 204, body: Data())
        } catch {
            return HTTPResponse(status: 400, body: Data("\(error)".utf8))
        }
    }

    private func scheduleErrorClear(sessionId: String) {
        let nanos = UInt64(config.behavior.errorAutoClearSeconds * 1_000_000_000)
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            await self.clearErrorIfStillError(sessionId: sessionId)
        }
        errorClearTasks[sessionId] = task
    }

    private func clearErrorIfStillError(sessionId: String) async {
        let snapshot = await store.snapshot()
        guard snapshot[sessionId]?.state == .error else { return }
        await store.setState(.idle, for: sessionId)
        errorClearTasks.removeValue(forKey: sessionId)
        await renderEffective()
    }

    private func renderEffective() async {
        // Debounce within debounceMillis. Cancel any pending render and schedule new.
        debounceTask?.cancel()
        let ms = config.behavior.debounceMillis
        if ms == 0 {
            await actuallyRender()
        } else {
            debounceTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.actuallyRender()
            }
        }
    }

    private func actuallyRender() async {
        let snapshot = await store.snapshot()
        let effective = Arbiter.compute(snapshot)
        await driver.render(effective)
    }

    private func handleState() async -> HTTPResponse {
        let snapshot = await store.snapshot()
        let effective = Arbiter.compute(snapshot)
        let body: [String: Any] = [
            "effective": effective.serializedName,
            "sessions": snapshot.mapValues { rec -> [String: Any] in
                ["state": rec.state.serializedName,
                 "since": rec.since.timeIntervalSince1970,
                 "cwd": rec.cwd as Any]
            },
        ]
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
        return HTTPResponse(status: 200, body: data)
    }

    private func handleTest(_ request: HTTPRequest) async -> HTTPResponse {
        guard let stateName = request.query["state"],
              let state = State.allCases.first(where: { $0.serializedName == stateName }) else {
            return HTTPResponse(status: 400, body: Data("invalid state".utf8))
        }
        await driver.render(state)
        return HTTPResponse(status: 204, body: Data())
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter VibeBrokerNetTests.EventRouterTests`
Expected: PASS — all 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeBrokerNet/EventRouter.swift Tests/VibeBrokerNetTests/EventRouterTests.swift
git commit -m "feat(net): add EventRouter with ERROR auto-clear and debounce"
```

---

## Task 17: EventRouter — `/state` `/test` `/health` smoke

Already implemented in Task 16. Add focused tests.

**Files:**
- Modify: `Tests/VibeBrokerNetTests/EventRouterTests.swift`

- [ ] **Step 1: Add tests**

Append to `EventRouterTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests**

Run: `swift test --filter VibeBrokerNetTests.EventRouterEndpointTests`
Expected: PASS — all 4 tests.

- [ ] **Step 3: Commit**

```bash
git add Tests/VibeBrokerNetTests/EventRouterTests.swift
git commit -m "test(net): cover /state /test /health and 404"
```

---

## Task 18: CLI executable + signal handling

**Files:**
- Modify: `Sources/vibelight-broker/App.swift`
- Create: `Resources/config.example.json`

CLI loads config from `~/.config/vibelight/config.json` (default) or `--config <path>`, starts listener, runs forever. SIGINT / SIGTERM trigger graceful shutdown.

- [ ] **Step 1: Replace `App.swift`**

`Sources/vibelight-broker/App.swift`:
```swift
import Foundation
import VibeBrokerCore
import VibeBrokerNet

@main
struct App {
    static func main() async throws {
        let configPath = parseConfigArg() ?? defaultConfigPath()
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            FileHandle.standardError.write(Data("config not found at \(configPath.path)\n".utf8))
            exit(2)
        }
        let config = try Config.loadFromDisk(configPath)
        let store = SessionStore(ttlSeconds: config.behavior.sessionTtlSeconds)
        let haClient = HAClient(
            baseURL: config.homeAssistant.url,
            token: config.homeAssistant.token
        )
        let driver = BrokerEmulatedDriver(client: haClient, config: config)
        let router = EventRouter(store: store, driver: driver, config: config)
        let listener = HTTPListener(port: config.broker.port) { request in
            await router.handle(request)
        }
        try await listener.start()

        let actualPort = await listener.boundPort()
        print("vibelight-broker: listening on 127.0.0.1:\(actualPort)")

        // Periodic TTL pruning every 60 s.
        let pruneTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                _ = await store.pruneExpired()
            }
        }
        defer { pruneTask.cancel() }

        // Block until SIGINT / SIGTERM.
        await waitForShutdownSignal()
        await listener.stop()
        print("vibelight-broker: stopped")
    }

    private static func parseConfigArg() -> URL? {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--config"), idx + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[idx + 1])
    }

    private static func defaultConfigPath() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/vibelight/config.json")
    }

    private static func waitForShutdownSignal() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
            let source2 = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
            signal(SIGINT, SIG_IGN)
            signal(SIGTERM, SIG_IGN)
            let handler = {
                source.cancel()
                source2.cancel()
                cont.resume()
            }
            source.setEventHandler(handler: handler)
            source2.setEventHandler(handler: handler)
            source.resume()
            source2.resume()
        }
    }
}
```

- [ ] **Step 2: Create example config**

`Resources/config.example.json`:
```json
{
  "broker": { "port": 17345 },
  "homeAssistant": {
    "url": "http://homeassistant.local:8123",
    "token": "REPLACE_WITH_LONG_LIVED_TOKEN",
    "lightEntity": "light.desk_strip"
  },
  "behavior": {
    "sessionTtlSeconds": 300,
    "errorAutoClearSeconds": 5,
    "doneBlinkSeconds": 2,
    "waitingInputBlinkSeconds": 3,
    "debounceMillis": 100
  },
  "colors": {
    "idle":         { "rgb": [80, 30, 120],  "brightness": 80,  "effect": "solid" },
    "working":      { "rgb": [40, 120, 255], "brightness": 200, "effect": "breathe" },
    "compacting":   { "rgb": [240, 220, 60], "brightness": 200, "effect": "breathe" },
    "waiting_input":{ "rgb": [255, 140, 30], "brightness": 220, "effect": "blink_then_solid" },
    "needs_auth":   { "rgb": [255, 30, 30],  "brightness": 230, "effect": "solid" },
    "error":        { "rgb": [255, 30, 30],  "brightness": 230, "effect": "blink" },
    "done":         { "rgb": [80, 30, 120],  "brightness": 200, "effect": "blink" }
  }
}
```

- [ ] **Step 3: Verify build**

Run: `swift build`
Expected: builds without errors.

- [ ] **Step 4: Smoke test — start and stop**

Run:
```bash
mkdir -p ~/.config/vibelight
cp Resources/config.example.json ~/.config/vibelight/config.json
# Edit ~/.config/vibelight/config.json to put a real HA URL and token (you can use a fake URL for this smoke; we won't hit it yet).
swift run vibelight-broker &
BROKER_PID=$!
sleep 1
curl -s http://127.0.0.1:17345/health
echo
kill -INT $BROKER_PID
wait $BROKER_PID
```

Expected output:
```
vibelight-broker: listening on 127.0.0.1:17345
{"ok":true}
vibelight-broker: stopped
```

- [ ] **Step 5: Commit**

```bash
git add Sources/vibelight-broker/App.swift Resources/config.example.json
git commit -m "feat(broker): wire CLI executable with signal handling"
```

---

## Task 19: Hook shell script + manual end-to-end test

**Files:**
- Create: `Resources/vibelight.sh`
- Create: `Resources/README-manual-test.md`

The hook script forwards Claude Code hook payloads to the broker. Used both at runtime and as the source of truth for what P3's HookInstaller writes.

- [ ] **Step 1: Create the hook script**

`Resources/vibelight.sh`:
```bash
#!/usr/bin/env bash
# vibelight: forward Claude Code hook payload to local broker.
# Argument $1 = hook name (e.g. PreToolUse). stdin = JSON payload.
# Fail silently — never block Claude Code.
exec curl -s -m 0.2 -X POST \
  -H 'Content-Type: application/json' \
  --data-binary @- \
  "http://127.0.0.1:17345/event?hook=$1" >/dev/null 2>&1 || true
```

Make executable:
```bash
chmod +x Resources/vibelight.sh
```

- [ ] **Step 2: Create manual test README**

`Resources/README-manual-test.md`:
````markdown
# Manual end-to-end smoke test

Prerequisites:
- `~/.config/vibelight/config.json` exists with valid HA URL, token, and `light.X` entity
- Home Assistant is reachable and the light entity responds

## 1. Start the broker

```bash
swift run vibelight-broker
```

Leave it running in one terminal.

## 2. Simulate a UserPromptSubmit (expect WORKING / breathing blue)

```bash
echo '{"session_id":"test1","cwd":"/tmp"}' | \
  curl -s -X POST -H 'Content-Type: application/json' \
       --data-binary @- \
       'http://127.0.0.1:17345/event?hook=UserPromptSubmit'
```

Light should turn blue and start breathing.

## 3. Simulate a Notification with permission (expect NEEDS_AUTH / solid red)

```bash
echo '{"session_id":"test1","message":"Claude needs your permission to use Bash"}' | \
  curl -s -X POST -H 'Content-Type: application/json' \
       --data-binary @- \
       'http://127.0.0.1:17345/event?hook=Notification'
```

Light should turn solid red.

## 4. Simulate Stop (expect DONE → IDLE)

```bash
echo '{"session_id":"test1"}' | \
  curl -s -X POST -H 'Content-Type: application/json' \
       --data-binary @- \
       'http://127.0.0.1:17345/event?hook=Stop'
```

Light should blink purple briefly, then settle to solid purple (IDLE).

## 5. Inspect state via /state

```bash
curl -s http://127.0.0.1:17345/state | python3 -m json.tool
```

## 6. Trigger any state directly via /test

```bash
curl -s -X POST 'http://127.0.0.1:17345/test?state=error'
```

## 7. Test ERROR auto-clear

```bash
curl -s -X POST 'http://127.0.0.1:17345/test?state=error'
# Wait 6 seconds.
sleep 6
# Light should have returned to whatever the effective_state is (likely IDLE).
```

Note: `/test` does NOT update session state, only renders the driver directly. To test the full auto-clear path, send a real `PostToolUse` with `is_error: true`:

```bash
echo '{"session_id":"test1","tool_response":{"is_error":true}}' | \
  curl -s -X POST -H 'Content-Type: application/json' \
       --data-binary @- \
       'http://127.0.0.1:17345/event?hook=PostToolUse'
sleep 6
curl -s http://127.0.0.1:17345/state | python3 -m json.tool
# Expect session state to be "idle"
```

## 8. Stop the broker

`Ctrl+C` in the broker terminal. Expect "vibelight-broker: stopped".
````

- [ ] **Step 3: Manually wire hook to a Claude Code session and verify end-to-end**

Optional smoke (do this if you have time / a quick Claude Code session handy — full hook integration is P3, but you can hand-wire for confidence):

In `~/.claude/settings.json`, add (back up the file first):
```json
{
  "hooks": {
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "/absolute/path/to/Resources/vibelight.sh UserPromptSubmit"}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "/absolute/path/to/Resources/vibelight.sh Stop"}]}]
  }
}
```

Then start a Claude Code session. The light should turn blue when you type a prompt and purple-blink when Claude finishes. **Remove these hooks after the smoke** — P3 introduces a proper installer.

- [ ] **Step 4: Commit**

```bash
git add Resources/vibelight.sh Resources/README-manual-test.md
git commit -m "feat: add Claude Code hook script and manual smoke instructions"
```

---

## Final verification

- [ ] **Run full test suite**

```bash
swift test
```

Expected: all tests pass. Approximate count: ~55 tests across both test targets.

- [ ] **Build release binary**

```bash
swift build -c release
ls -lh .build/release/vibelight-broker
```

Expected: binary exists. Size approximately 2–4 MB.

- [ ] **Tag P1 milestone**

```bash
git tag p1-broker-core
```

---

## P1 Done. What's next?

P1 produces a working headless broker. To call P1 complete:

1. `swift test` is green
2. Manual end-to-end test (Resources/README-manual-test.md) hits a real HA and changes the light
3. Optional: hand-wiring `~/.claude/settings.json` to `vibelight.sh` makes the light respond to real Claude Code activity

**Next: P2 (macOS app shell).** P2 wraps this broker logic inside a SwiftUI menubar application — same code, different entry point. Specifically: replace `vibelight-broker` executable target with an Xcode-built `.app`, add `MenuBarController`, `SessionsWindow`, `Settings` (Phase A only — full settings is P3).
