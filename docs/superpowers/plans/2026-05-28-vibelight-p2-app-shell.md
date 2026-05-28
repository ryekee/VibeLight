# VibeLight P2: macOS Menubar App Shell — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wrap P1's headless broker in a SwiftUI menubar application: a colored menubar icon that reflects the current effective state, plus menu items for Pause / Test light effect / Show sessions / Settings (placeholder for P3) / Quit. The broker keeps running inside the app.

**Architecture:** Add a `BrokerHost` actor in `VibeBrokerNet` that owns the full broker wiring (Config + Store + Driver + Router + Listener); both the existing `vibelight-broker` CLI and the new `vibelight-app` SwiftUI target use it. SwiftUI app uses `MenuBarExtra` scene; an `@MainActor ObservableObject` view-model bridges actor state to SwiftUI via a callback the broker invokes on every effective-state change. A `bundle.sh` script wraps the binary into a `.app` for distribution (Xcode project deferred to P3 if code signing becomes a concern).

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 13+, Foundation. Zero third-party dependencies.

**Scope (P2 only):**
- New `BrokerHost` actor (broker wiring extraction)
- `EventRouter` observer callback for state-change notifications
- `EventRouter` Pause flag (mutes driver but keeps state tracking)
- New `vibelight-app` SwiftPM executable target with SwiftUI
- `MenuBarExtra`-based menubar icon (colored SF Symbol, static; no animation in icon)
- Menu: status row, Pause submenu, Test light effect submenu, Sessions submenu, Show Sessions window, Settings menu item (placeholder), Quit
- Show Sessions separate window
- Settings empty placeholder window
- `bundle.sh` for .app packaging
- Manual end-to-end smoke test instructions

**Out of scope (deferred to P3):**
- Onboarding flow
- Real Settings UI (HA URL/token/light entity editor; Colors editor; Hook installer button; Scene pack mode toggle)
- `HomeReachability` / `HADiscovery`
- Scene pack driver + installer
- Hook installer (writes `~/.claude/settings.json`)
- Icon animations (breathing/blinking on the menubar icon itself)
- Code signing / notarization (`bundle.sh` produces an unsigned .app)

**Why this scope:** P2 delivers a launchable .app that responds to fake events with visible icon changes. Validates the SwiftUI plumbing without yet committing to onboarding UI choices.

---

## File Structure

```
VibeLight/
├── Package.swift                        # MODIFY: add vibelight-app executable target
├── Sources/
│   ├── VibeBrokerCore/                  # unchanged
│   ├── VibeBrokerNet/
│   │   ├── EventRouter.swift            # MODIFY: add observer callback + paused flag
│   │   ├── BrokerHost.swift             # NEW: full broker wiring as one actor
│   │   └── ... (others unchanged)
│   ├── vibelight-broker/
│   │   └── App.swift                    # MODIFY: thin wrapper around BrokerHost
│   └── vibelight-app/                   # NEW: SwiftUI executable target
│       ├── VibeLightApp.swift           # @main, MenuBarExtra scene
│       ├── AppViewModel.swift           # @MainActor ObservableObject bridging broker → UI
│       ├── MenuContent.swift            # Menu items (status, pause, test, sessions, settings, quit)
│       ├── StateAppearance.swift        # State → Color/SF Symbol mapping
│       ├── SessionsWindow.swift         # Show Sessions window content
│       ├── SettingsPlaceholderWindow.swift # P3 placeholder
│       └── Info.plist                   # LSUIElement=true (no Dock icon)
├── Tests/
│   ├── VibeBrokerCoreTests/             # unchanged
│   └── VibeBrokerNetTests/
│       ├── EventRouterTests.swift       # ADD: observer + pause tests
│       └── BrokerHostTests.swift        # NEW
└── scripts/
    └── bundle.sh                        # NEW: wraps binary as .app
```

---

## Task Index

| # | Task | Test layer |
|---|---|---|
| 1 | EventRouter: effective-state observer callback | unit |
| 2 | EventRouter: Pause flag (mutes driver, keeps state) | unit |
| 3 | BrokerHost actor (wraps Config → Store → Driver → Router → Listener) | unit |
| 4 | Migrate `vibelight-broker` CLI to BrokerHost | refactor (existing tests pass) |
| 5 | Add `vibelight-app` SwiftPM target + Info.plist + scaffold `@main` | build only |
| 6 | AppViewModel + state→color mapping | manual smoke |
| 7 | MenuBarExtra colored icon + status row | manual smoke |
| 8 | Pause submenu wiring | manual smoke |
| 9 | Test light effect + Sessions submenus | manual smoke |
| 10 | Show Sessions window + Settings placeholder window + Quit | manual smoke |
| 11 | `bundle.sh` packaging script + end-to-end .app smoke | manual smoke |

---

## Task 1: EventRouter — effective-state observer callback

**Files:**
- Modify: `Sources/VibeBrokerNet/EventRouter.swift`
- Modify: `Tests/VibeBrokerNetTests/EventRouterTests.swift`

EventRouter needs to notify external observers whenever the effective state changes. Add a `@Sendable (State) async -> Void` callback set via `setObserver(_:)`. The router invokes it after each `actuallyRender()` call.

- [ ] **Step 1: Add failing test**

Append to `Tests/VibeBrokerNetTests/EventRouterTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VibeBrokerNetTests.EventRouterObserverTests`
Expected: FAIL — `setObserver` not defined.

- [ ] **Step 3: Add observer support to EventRouter**

In `Sources/VibeBrokerNet/EventRouter.swift`, add inside the actor:

```swift
public typealias EffectiveStateObserver = @Sendable (State) async -> Void

private var observer: EffectiveStateObserver?

public func setObserver(_ observer: @escaping EffectiveStateObserver) {
    self.observer = observer
}
```

Then modify `actuallyRender()` to invoke the observer. Current:

```swift
private func actuallyRender() async {
    let snapshot = await store.snapshot()
    let effective = Arbiter.compute(snapshot)
    await driver.render(effective)
}
```

Replace with:

```swift
private func actuallyRender() async {
    let snapshot = await store.snapshot()
    let effective = Arbiter.compute(snapshot)
    await driver.render(effective)
    if let observer { await observer(effective) }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter VibeBrokerNetTests.EventRouterObserverTests`
Expected: PASS.

Run: `swift test`
Expected: full suite still passes (59 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeBrokerNet/EventRouter.swift Tests/VibeBrokerNetTests/EventRouterTests.swift
git commit -m "feat(net): add effective-state observer callback to EventRouter"
```

---

## Task 2: EventRouter — Pause flag

**Files:**
- Modify: `Sources/VibeBrokerNet/EventRouter.swift`
- Modify: `Tests/VibeBrokerNetTests/EventRouterTests.swift`

Pause mutes the **driver** (no HA calls) but keeps state tracking and observer notifications running. Spec §6.6.

- [ ] **Step 1: Add failing test**

Append to `Tests/VibeBrokerNetTests/EventRouterTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter VibeBrokerNetTests.EventRouterPauseTests`
Expected: FAIL — `setPaused` not defined.

- [ ] **Step 3: Add pause support to EventRouter**

In `Sources/VibeBrokerNet/EventRouter.swift`, add inside the actor:

```swift
private var paused: Bool = false

public func setPaused(_ paused: Bool) async {
    let wasResumed = self.paused && !paused
    self.paused = paused
    if wasResumed {
        await actuallyRender()
    }
}

public func isPaused() -> Bool { paused }
```

Then modify `actuallyRender()` to skip the driver when paused. Current (post-Task-1):

```swift
private func actuallyRender() async {
    let snapshot = await store.snapshot()
    let effective = Arbiter.compute(snapshot)
    await driver.render(effective)
    if let observer { await observer(effective) }
}
```

Replace with:

```swift
private func actuallyRender() async {
    let snapshot = await store.snapshot()
    let effective = Arbiter.compute(snapshot)
    if !paused {
        await driver.render(effective)
    }
    if let observer { await observer(effective) }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter VibeBrokerNetTests.EventRouterPauseTests`
Expected: PASS.

Run: `swift test`
Expected: 61 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeBrokerNet/EventRouter.swift Tests/VibeBrokerNetTests/EventRouterTests.swift
git commit -m "feat(net): add Pause flag to EventRouter (mutes driver, keeps state)"
```

---

## Task 3: `BrokerHost` actor

**Files:**
- Create: `Sources/VibeBrokerNet/BrokerHost.swift`
- Create: `Tests/VibeBrokerNetTests/BrokerHostTests.swift`

`BrokerHost` owns the full broker wiring. Single entry points for both CLI and app:

```swift
let host = try await BrokerHost(config: config)
try await host.start()
// ... use it ...
await host.stop()
```

- [ ] **Step 1: Write failing tests**

Create `Tests/VibeBrokerNetTests/BrokerHostTests.swift`:

```swift
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
        XCTAssertTrue(await host.isPaused())
        await host.setPaused(false)
        XCTAssertFalse(await host.isPaused())
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter VibeBrokerNetTests.BrokerHostTests`
Expected: FAIL — `BrokerHost` not defined.

- [ ] **Step 3: Implement `BrokerHost.swift`**

Create `Sources/VibeBrokerNet/BrokerHost.swift`:

```swift
import Foundation
import VibeBrokerCore

public actor BrokerHost {
    private let config: Config
    private let store: SessionStore
    private let haClient: HAClient
    private let driver: BrokerEmulatedDriver
    private let router: EventRouter
    private let listener: HTTPListener

    private var pruneTask: Task<Void, Never>?

    public init(config: Config) {
        self.config = config
        self.store = SessionStore(ttlSeconds: config.behavior.sessionTtlSeconds)
        self.haClient = HAClient(
            baseURL: config.homeAssistant.url,
            token: config.homeAssistant.token
        )
        self.driver = BrokerEmulatedDriver(client: haClient, config: config)
        self.router = EventRouter(store: store, driver: driver, config: config)
        let router = self.router
        self.listener = HTTPListener(port: config.broker.port) { request in
            await router.handle(request)
        }
    }

    public func start() async throws {
        try await listener.start()
        let store = self.store
        pruneTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                _ = await store.pruneExpired()
            }
        }
    }

    public func stop() async {
        pruneTask?.cancel()
        pruneTask = nil
        await listener.stop()
        await driver.cancel()
    }

    public func boundPort() async -> UInt16 {
        await listener.boundPort()
    }

    public func setObserver(_ observer: @escaping EventRouter.EffectiveStateObserver) async {
        await router.setObserver(observer)
    }

    public func setPaused(_ paused: Bool) async {
        await router.setPaused(paused)
    }

    public func isPaused() async -> Bool {
        await router.isPaused()
    }

    public func sessionSnapshot() async -> [String: SessionRecord] {
        await store.snapshot()
    }

    /// Trigger a one-off driver render (used by Test light effect menu).
    public func testRender(_ state: State) async {
        await driver.render(state)
    }
}
```

Note: `HTTPListener.boundPort()` and `HTTPListener.stop()` were made non-async in P1 — `await` on a non-async actor method is still valid (it's the cross-actor hop that's awaited). The call sites above are correct.

- [ ] **Step 4: Run tests**

Run: `swift test --filter VibeBrokerNetTests.BrokerHostTests`
Expected: PASS — 4 tests.

Run: `swift test`
Expected: 65 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeBrokerNet/BrokerHost.swift Tests/VibeBrokerNetTests/BrokerHostTests.swift
git commit -m "feat(net): add BrokerHost actor wrapping full broker wiring"
```

---

## Task 4: Migrate `vibelight-broker` CLI to use BrokerHost

**Files:**
- Modify: `Sources/vibelight-broker/App.swift`

Replace the manual wiring in `App.swift` with a `BrokerHost`.

- [ ] **Step 1: Rewrite `App.swift`**

Replace contents of `Sources/vibelight-broker/App.swift`:

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
        let host = BrokerHost(config: config)
        try await host.start()

        let actualPort = await host.boundPort()
        print("vibelight-broker: listening on 127.0.0.1:\(actualPort)")

        await waitForShutdownSignal()
        await host.stop()
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

The diff: the wiring (`SessionStore`, `HAClient`, `BrokerEmulatedDriver`, `EventRouter`, `HTTPListener`) plus periodic prune task all moved into `BrokerHost`. CLI is now ~40 lines.

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: clean.

- [ ] **Step 3: Run full test suite**

Run: `swift test 2>&1 | tail -5`
Expected: 65 tests pass.

- [ ] **Step 4: CLI smoke test**

```bash
swift run vibelight-broker &
BROKER_PID=$!
sleep 2
curl -s http://127.0.0.1:17345/health
echo
kill -INT $BROKER_PID
wait $BROKER_PID 2>/dev/null
```

Expected output:
```
vibelight-broker: listening on 127.0.0.1:17345
{"ok":true}
vibelight-broker: stopped
```

- [ ] **Step 5: Commit**

```bash
git add Sources/vibelight-broker/App.swift
git commit -m "refactor(broker): use BrokerHost for CLI wiring"
```

---

## Task 5: Add `vibelight-app` SwiftPM target + Info.plist + scaffold

**Files:**
- Modify: `Package.swift`
- Create: `Sources/vibelight-app/VibeLightApp.swift`
- Create: `Sources/vibelight-app/Info.plist`

- [ ] **Step 1: Update `Package.swift`**

Replace contents of `Package.swift`:

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
        .executable(name: "vibelight-app", targets: ["vibelight-app"]),
    ],
    targets: [
        .target(name: "VibeBrokerCore"),
        .target(name: "VibeBrokerNet", dependencies: ["VibeBrokerCore"]),
        .executableTarget(
            name: "vibelight-broker",
            dependencies: ["VibeBrokerCore", "VibeBrokerNet"]
        ),
        .executableTarget(
            name: "vibelight-app",
            dependencies: ["VibeBrokerCore", "VibeBrokerNet"],
            resources: [.copy("Info.plist")]
        ),
        .testTarget(name: "VibeBrokerCoreTests", dependencies: ["VibeBrokerCore"]),
        .testTarget(
            name: "VibeBrokerNetTests",
            dependencies: ["VibeBrokerNet", "VibeBrokerCore"]
        ),
    ]
)
```

- [ ] **Step 2: Create stub `VibeLightApp.swift`**

`Sources/vibelight-app/VibeLightApp.swift`:

```swift
import SwiftUI

@main
struct VibeLightApp: App {
    var body: some Scene {
        MenuBarExtra("VibeLight", systemImage: "circle.fill") {
            Text("VibeLight (scaffold)")
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
```

- [ ] **Step 3: Create Info.plist**

`Sources/vibelight-app/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.vibelight.app</string>
    <key>CFBundleName</key>
    <string>VibeLight</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.0</string>
    <key>CFBundleVersion</key>
    <string>0.2.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
```

`LSUIElement=true` hides the Dock icon (menubar-only app). This Info.plist is bundled by `bundle.sh` (Task 11); it's not consulted when running via `swift run`.

- [ ] **Step 4: Verify build**

Run: `swift build`
Expected: clean, all 4 products build (2 libs + 2 execs).

- [ ] **Step 5: Sanity-run the app**

Run: `swift run vibelight-app &`
Wait 2 seconds. Look at the menubar — there should be a circle.fill icon. Click it; you should see "VibeLight (scaffold)" and a Quit button.

Click Quit (or `pkill vibelight-app`). Confirm process exits.

Note: `swift run vibelight-app` does NOT install Info.plist's `LSUIElement=true` (no bundle). So the Dock icon will appear during dev. That's fine — the bundle wrapper in Task 11 will hide it for the .app distribution.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/vibelight-app
git commit -m "feat(app): scaffold vibelight-app SwiftPM target with MenuBarExtra stub"
```

---

## Task 6: AppViewModel + state→color mapping

**Files:**
- Create: `Sources/vibelight-app/StateAppearance.swift`
- Create: `Sources/vibelight-app/AppViewModel.swift`

`AppViewModel` is a `@MainActor`-isolated `ObservableObject` that hosts the `BrokerHost` and republishes its effective state as a `@Published` property. SwiftUI observes the published property; on changes, the menubar icon updates.

- [ ] **Step 1: Create `StateAppearance.swift`**

`Sources/vibelight-app/StateAppearance.swift`:

```swift
import SwiftUI
import VibeBrokerCore

enum StateAppearance {
    /// Maps a logical state to a menubar-icon color. Mirrors spec §2 (light colors;
    /// the menubar icon is a static colored circle — animations live on the real light).
    static func color(_ state: State) -> Color {
        switch state {
        case .idle, .done:    return Color(red: 0.31, green: 0.12, blue: 0.47) // purple
        case .working:        return Color(red: 0.16, green: 0.47, blue: 1.00) // blue
        case .compacting:     return Color(red: 0.94, green: 0.86, blue: 0.24) // yellow
        case .waitingInput:   return Color(red: 1.00, green: 0.55, blue: 0.12) // orange
        case .needsAuth,
             .error:          return Color(red: 1.00, green: 0.12, blue: 0.12) // red
        }
    }

    /// Short human label shown in the status row of the menu.
    static func label(_ state: State) -> String {
        switch state {
        case .idle:          return "Idle"
        case .done:          return "Done"
        case .working:       return "Working"
        case .compacting:    return "Compacting"
        case .waitingInput:  return "Waiting for input"
        case .needsAuth:     return "Needs your approval"
        case .error:         return "Error"
        }
    }
}
```

- [ ] **Step 2: Create `AppViewModel.swift`**

`Sources/vibelight-app/AppViewModel.swift`:

```swift
import SwiftUI
import VibeBrokerCore
import VibeBrokerNet

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var effectiveState: State = .idle
    @Published private(set) var sessions: [SessionRecord] = []
    @Published private(set) var paused: Bool = false
    @Published private(set) var listening: Bool = false
    @Published private(set) var lastError: String?

    private var host: BrokerHost?
    private var refreshTask: Task<Void, Never>?

    func bootstrap() {
        guard host == nil else { return }
        Task {
            do {
                let configPath = Self.defaultConfigPath()
                guard FileManager.default.fileExists(atPath: configPath.path) else {
                    self.lastError = "config not found at \(configPath.path)"
                    return
                }
                let config = try Config.loadFromDisk(configPath)
                let host = BrokerHost(config: config)
                await host.setObserver { [weak self] state in
                    await self?.updateEffective(state)
                }
                try await host.start()
                self.host = host
                self.listening = true
                self.startSessionRefresh()
            } catch {
                self.lastError = String(describing: error)
            }
        }
    }

    func shutdown() async {
        refreshTask?.cancel()
        refreshTask = nil
        await host?.stop()
        host = nil
        listening = false
    }

    func setPaused(_ paused: Bool) {
        Task {
            await host?.setPaused(paused)
            self.paused = paused
        }
    }

    func testRender(_ state: State) {
        Task { await host?.testRender(state) }
    }

    private func updateEffective(_ state: State) {
        Task { @MainActor in
            self.effectiveState = state
        }
    }

    private func startSessionRefresh() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let snapshot = await self.host?.sessionSnapshot() {
                    let sorted = snapshot.values.sorted { $0.since > $1.since }
                    await MainActor.run { self.sessions = sorted }
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private static func defaultConfigPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/vibelight/config.json")
    }
}
```

Note on the observer hop: BrokerHost's observer fires on its actor; we hop to MainActor in `updateEffective` so SwiftUI's `@Published` update happens on the main thread.

- [ ] **Step 3: Verify build**

Run: `swift build`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add Sources/vibelight-app/StateAppearance.swift Sources/vibelight-app/AppViewModel.swift
git commit -m "feat(app): add AppViewModel and StateAppearance for SwiftUI"
```

---

## Task 7: MenuBarExtra colored icon + status row

**Files:**
- Modify: `Sources/vibelight-app/VibeLightApp.swift`
- Create: `Sources/vibelight-app/MenuContent.swift`

- [ ] **Step 1: Rewrite `VibeLightApp.swift`**

`Sources/vibelight-app/VibeLightApp.swift`:

```swift
import SwiftUI

@main
struct VibeLightApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(viewModel: viewModel)
        } label: {
            Image(systemName: "circle.fill")
                .foregroundColor(StateAppearance.color(viewModel.effectiveState))
        }
        .menuBarExtraStyle(.menu)
    }

    init() {
        // Bootstrapping in `init` because we need the broker running by the time the
        // menubar item appears. AppViewModel.bootstrap() is idempotent.
    }
}
```

Wait — `@StateObject` is created at first body access. We need bootstrap to fire on app launch. Use `.onAppear` won't work for MenuBarExtra (no view lifecycle). Use Task in init:

Replace with this final form:

```swift
import SwiftUI

@main
struct VibeLightApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(viewModel: viewModel)
                .task { viewModel.bootstrap() }
        } label: {
            Image(systemName: "circle.fill")
                .foregroundColor(StateAppearance.color(viewModel.effectiveState))
        }
        .menuBarExtraStyle(.menu)
    }
}
```

`.task` fires when the menu content is first instantiated (i.e., when the user first opens the menu). For our purposes that's acceptable — the icon shows a default purple until the menu is opened. If the user wants the broker to start immediately on launch, they can open the menu once. (P3 can move bootstrap into a launch-time hook if needed.)

Actually that's not great UX. Let me instead trigger bootstrap from the AppViewModel's `init`:

Update `AppViewModel.swift` — add an init that calls bootstrap:

```swift
init() {
    bootstrap()
}
```

Then remove `.task { viewModel.bootstrap() }` from VibeLightApp.swift.

So final `VibeLightApp.swift`:

```swift
import SwiftUI

@main
struct VibeLightApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(viewModel: viewModel)
        } label: {
            Image(systemName: "circle.fill")
                .foregroundColor(StateAppearance.color(viewModel.effectiveState))
        }
        .menuBarExtraStyle(.menu)
    }
}
```

And add to `AppViewModel.swift`:

```swift
init() { bootstrap() }
```

(insert immediately before `func bootstrap()`).

- [ ] **Step 2: Create `MenuContent.swift` (status row only for now)**

`Sources/vibelight-app/MenuContent.swift`:

```swift
import SwiftUI
import VibeBrokerCore

struct MenuContent: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        statusSection
        Divider()
        Button("Quit VibeLight") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusSection: some View {
        Group {
            if let err = viewModel.lastError {
                Text("⚠️ \(err)")
            } else if !viewModel.listening {
                Text("Starting broker…")
            } else {
                Text(StateAppearance.label(viewModel.effectiveState))
                Text("Sessions: \(viewModel.sessions.count)")
                    .font(.caption)
            }
        }
    }
}
```

- [ ] **Step 3: Verify build**

Run: `swift build`
Expected: clean.

- [ ] **Step 4: Manual smoke**

```bash
swift run vibelight-app &
APP_PID=$!
sleep 3
```

Look at menubar: should see a colored circle. Open it (click). Should see "Working" or "Idle" (depending on whether broker found a config), Sessions count 0, Quit.

In a second terminal, push a fake hook event:

```bash
echo '{"session_id":"manual1"}' | curl -s -X POST -H 'Content-Type: application/json' \
  --data-binary @- 'http://127.0.0.1:17345/event?hook=UserPromptSubmit'
```

Within 1 second the icon should turn blue (working), and reopening the menu should show "Working" + "Sessions: 1".

Quit the app:
```bash
kill $APP_PID; wait $APP_PID 2>/dev/null
```

**If you can't yet test against config** (`~/.config/vibelight/config.json` not present): the app should show "⚠️ config not found at …" in the menu. That's acceptable — it confirms the error path. Create the config (`cp Resources/config.example.json ~/.config/vibelight/config.json`) and re-run.

- [ ] **Step 5: Commit**

```bash
git add Sources/vibelight-app
git commit -m "feat(app): wire MenuBarExtra to AppViewModel with status row"
```

---

## Task 8: Pause submenu

**Files:**
- Modify: `Sources/vibelight-app/MenuContent.swift`
- Modify: `Sources/vibelight-app/AppViewModel.swift`

Pause durations: 30 min, 1 hour, "Until 6 AM tomorrow". A `PauseScheduler` inside AppViewModel handles the auto-resume timer.

- [ ] **Step 1: Add pause scheduling to AppViewModel**

Modify `Sources/vibelight-app/AppViewModel.swift`. Add this property at the top of the class (next to `private var refreshTask`):

```swift
private var pauseResumeTask: Task<Void, Never>?
@Published private(set) var pauseUntil: Date?
```

Add this method at the bottom of the class (just before `private static func defaultConfigPath`):

```swift
func pauseFor(_ duration: PauseDuration) {
    let resumeAt = duration.resumeDate(now: Date())
    pauseUntil = resumeAt
    setPaused(true)
    pauseResumeTask?.cancel()
    pauseResumeTask = Task { [weak self] in
        let nanos = UInt64(max(0, resumeAt.timeIntervalSinceNow) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanos)
        guard !Task.isCancelled else { return }
        await MainActor.run {
            self?.resume()
        }
    }
}

func resume() {
    pauseResumeTask?.cancel()
    pauseResumeTask = nil
    pauseUntil = nil
    setPaused(false)
}
```

And replace the existing `setPaused(_:)` with this private-flavored variant (we now have the public `pauseFor` and `resume`):

```swift
private func setPaused(_ paused: Bool) {
    Task {
        await host?.setPaused(paused)
        await MainActor.run { self.paused = paused }
    }
}
```

Add a new file `Sources/vibelight-app/PauseDuration.swift`:

```swift
import Foundation

enum PauseDuration {
    case thirtyMinutes
    case oneHour
    case untilTomorrow

    var label: String {
        switch self {
        case .thirtyMinutes:  return "Pause for 30 minutes"
        case .oneHour:        return "Pause for 1 hour"
        case .untilTomorrow:  return "Pause until tomorrow"
        }
    }

    func resumeDate(now: Date) -> Date {
        switch self {
        case .thirtyMinutes:
            return now.addingTimeInterval(30 * 60)
        case .oneHour:
            return now.addingTimeInterval(60 * 60)
        case .untilTomorrow:
            let cal = Calendar.current
            var components = cal.dateComponents([.year, .month, .day], from: now)
            components.day = (components.day ?? 0) + 1
            components.hour = 6
            components.minute = 0
            components.second = 0
            return cal.date(from: components) ?? now.addingTimeInterval(8 * 60 * 60)
        }
    }
}
```

- [ ] **Step 2: Wire Pause submenu into MenuContent**

Modify `Sources/vibelight-app/MenuContent.swift`. Replace the body:

```swift
var body: some View {
    statusSection
    Divider()
    pauseSection
    Divider()
    Button("Quit VibeLight") { NSApplication.shared.terminate(nil) }
        .keyboardShortcut("q")
}

private var pauseSection: some View {
    Group {
        if let until = viewModel.pauseUntil {
            Text("Paused until \(formatted(until))")
            Button("Resume") { viewModel.resume() }
        } else {
            Menu("Pause") {
                Button(PauseDuration.thirtyMinutes.label) { viewModel.pauseFor(.thirtyMinutes) }
                Button(PauseDuration.oneHour.label)      { viewModel.pauseFor(.oneHour) }
                Button(PauseDuration.untilTomorrow.label){ viewModel.pauseFor(.untilTomorrow) }
            }
        }
    }
}

private func formatted(_ date: Date) -> String {
    let f = DateFormatter()
    f.timeStyle = .short
    f.dateStyle = .none
    return f.string(from: date)
}
```

- [ ] **Step 3: Verify build**

Run: `swift build`
Expected: clean.

- [ ] **Step 4: Manual smoke**

```bash
swift run vibelight-app &
sleep 2
```

Click menubar icon → click "Pause" → "Pause for 30 minutes". Menu should now show "Paused until 16:23" (or whatever time) and "Resume". Click Resume; pause should clear and the icon should resume reflecting state.

Quick verification that pause actually mutes the driver: while paused, send a fake event:
```bash
echo '{"session_id":"p1"}' | curl -s -X POST -H 'Content-Type: application/json' \
  --data-binary @- 'http://127.0.0.1:17345/event?hook=UserPromptSubmit'
```
The icon SHOULD update to blue (sessions are tracked even during pause), but the actual HA light should NOT be called. You can verify this by checking the broker logs (no HA call). If you're not in front of a real HA, this is invisible — but the code path is exercised.

Kill the app: `pkill vibelight-app`.

- [ ] **Step 5: Commit**

```bash
git add Sources/vibelight-app
git commit -m "feat(app): add Pause submenu with 30min/1h/until-tomorrow auto-resume"
```

---

## Task 9: Test light effect + Sessions submenus

**Files:**
- Modify: `Sources/vibelight-app/MenuContent.swift`

- [ ] **Step 1: Add Test + Sessions submenus**

Modify `Sources/vibelight-app/MenuContent.swift`. Replace `body`:

```swift
var body: some View {
    statusSection
    Divider()
    sessionsSection
    pauseSection
    testSection
    Divider()
    Button("Show Sessions Window…") { /* wired in Task 10 */ }
    Button("Settings…")            { /* wired in Task 10 */ }
    Divider()
    Button("Quit VibeLight") { NSApplication.shared.terminate(nil) }
        .keyboardShortcut("q")
}
```

Add two private sections inside the struct (before `pauseSection`):

```swift
private var sessionsSection: some View {
    Menu("Sessions (\(viewModel.sessions.count))") {
        if viewModel.sessions.isEmpty {
            Text("No active sessions").foregroundColor(.secondary)
        } else {
            ForEach(viewModel.sessions, id: \.id) { rec in
                Text("\(StateAppearance.label(rec.state)) — \(rec.cwd ?? rec.id.prefix(8).description)")
            }
        }
    }
}

private var testSection: some View {
    Menu("Test light effect") {
        ForEach(State.allCases, id: \.self) { state in
            Button(StateAppearance.label(state)) { viewModel.testRender(state) }
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: clean.

- [ ] **Step 3: Manual smoke**

```bash
swift run vibelight-app &
sleep 2
```

Menu should now show:
- Status (Idle/Working/etc.)
- Sessions submenu (probably "Sessions (0)" → "No active sessions")
- Pause submenu
- Test light effect submenu (7 entries)
- Show Sessions Window / Settings (no-op buttons for now)
- Quit

Send a fake event:
```bash
echo '{"session_id":"s1","cwd":"/Users/test/repo-a"}' | curl -s -X POST \
  -H 'Content-Type: application/json' --data-binary @- \
  'http://127.0.0.1:17345/event?hook=UserPromptSubmit'
```

Reopen the menu. Sessions submenu should show "Sessions (1)" → "Working — /Users/test/repo-a".

Click "Test light effect → Error". If you have HA, the light will blink red. Without HA, the action fires but the call times out silently (visible in HA-side logs / broker stderr if any).

Kill the app: `pkill vibelight-app`.

- [ ] **Step 4: Commit**

```bash
git add Sources/vibelight-app/MenuContent.swift
git commit -m "feat(app): add Sessions and Test-light-effect submenus"
```

---

## Task 10: Show Sessions window + Settings placeholder + Quit wiring

**Files:**
- Create: `Sources/vibelight-app/SessionsWindow.swift`
- Create: `Sources/vibelight-app/SettingsPlaceholderWindow.swift`
- Modify: `Sources/vibelight-app/VibeLightApp.swift`
- Modify: `Sources/vibelight-app/MenuContent.swift`

- [ ] **Step 1: Create `SessionsWindow.swift`**

`Sources/vibelight-app/SessionsWindow.swift`:

```swift
import SwiftUI
import VibeBrokerCore

struct SessionsWindow: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("VibeLight Sessions").font(.headline)
                Spacer()
                Text(viewModel.listening ? "Listening" : "Stopped")
                    .foregroundColor(viewModel.listening ? .green : .red)
            }
            Divider()
            if viewModel.sessions.isEmpty {
                Text("No active sessions").foregroundColor(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(viewModel.sessions) {
                    TableColumn("Session ID") { rec in Text(rec.id.prefix(8).description) }
                    TableColumn("State")      { rec in Text(StateAppearance.label(rec.state)) }
                    TableColumn("Since")      { rec in Text(rec.since.formatted(date: .omitted, time: .shortened)) }
                    TableColumn("CWD")        { rec in Text(rec.cwd ?? "—") }
                }
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 240)
    }
}
```

- [ ] **Step 2: Create `SettingsPlaceholderWindow.swift`**

`Sources/vibelight-app/SettingsPlaceholderWindow.swift`:

```swift
import SwiftUI

struct SettingsPlaceholderWindow: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gear")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Settings UI coming in P3").font(.headline)
            Text("For now, edit ~/.config/vibelight/config.json directly.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(40)
        .frame(width: 360, height: 200)
    }
}
```

- [ ] **Step 3: Add Window scenes to `VibeLightApp.swift`**

Replace `Sources/vibelight-app/VibeLightApp.swift`:

```swift
import SwiftUI

@main
struct VibeLightApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(viewModel: viewModel)
        } label: {
            Image(systemName: "circle.fill")
                .foregroundColor(StateAppearance.color(viewModel.effectiveState))
        }
        .menuBarExtraStyle(.menu)

        Window("VibeLight Sessions", id: "sessions") {
            SessionsWindow(viewModel: viewModel)
        }
        .windowResizability(.contentMinSize)

        Window("VibeLight Settings", id: "settings") {
            SettingsPlaceholderWindow()
        }
        .windowResizability(.contentSize)
    }
}
```

- [ ] **Step 4: Wire the menu buttons to open the windows**

Modify `Sources/vibelight-app/MenuContent.swift`. Add `@Environment(\.openWindow)` at the top of the struct:

```swift
struct MenuContent: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.openWindow) private var openWindow
    // ... existing body and helpers
```

Replace the two no-op buttons in `body` with:

```swift
Button("Show Sessions Window…") { openWindow(id: "sessions") }
Button("Settings…")            { openWindow(id: "settings") }
```

- [ ] **Step 5: Verify build**

Run: `swift build`
Expected: clean.

- [ ] **Step 6: Manual smoke**

```bash
swift run vibelight-app &
sleep 2
```

Open the menu:
- Click "Show Sessions Window…" → a new window titled "VibeLight Sessions" appears with the sessions table (likely empty initially)
- Click "Settings…" → a small window with the placeholder text appears
- Click "Quit" → both windows close and the process exits cleanly

Push a fake event from another terminal:
```bash
echo '{"session_id":"win-test","cwd":"/tmp/repo"}' | curl -s -X POST \
  -H 'Content-Type: application/json' --data-binary @- \
  'http://127.0.0.1:17345/event?hook=UserPromptSubmit'
```

The Sessions Window table should update within ~1 second (driven by the 1 Hz refresh in `AppViewModel.startSessionRefresh`).

- [ ] **Step 7: Commit**

```bash
git add Sources/vibelight-app
git commit -m "feat(app): add Sessions and Settings windows; wire menu buttons"
```

---

## Task 11: `bundle.sh` packaging + end-to-end .app smoke

**Files:**
- Create: `scripts/bundle.sh`
- Create: `Resources/README-app-smoke.md`

- [ ] **Step 1: Create the bundle script**

`scripts/bundle.sh`:

```bash
#!/usr/bin/env bash
# bundle.sh — wrap the vibelight-app executable into a runnable VibeLight.app.
# Produces ./build/VibeLight.app. Unsigned; for development use only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG=${CONFIG:-release}
APP_NAME="VibeLight"
APP_DIR="build/${APP_NAME}.app"
BIN_NAME="vibelight-app"

echo "==> Building (${CONFIG})"
swift build -c "$CONFIG"

BIN_PATH=$(swift build -c "$CONFIG" --show-bin-path)/$BIN_NAME
if [ ! -x "$BIN_PATH" ]; then
  echo "ERROR: built binary not found at $BIN_PATH"
  exit 1
fi

echo "==> Creating bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "Sources/vibelight-app/Info.plist" "$APP_DIR/Contents/Info.plist"

# Patch CFBundleExecutable to match the renamed binary
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$APP_DIR/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$APP_DIR/Contents/Info.plist"

echo "==> Done: $APP_DIR"
echo "Launch: open $APP_DIR"
```

Make it executable:
```bash
chmod +x scripts/bundle.sh
```

- [ ] **Step 2: Run the bundle script**

```bash
./scripts/bundle.sh
```

Expected: builds release binary (~3-5 MB), creates `build/VibeLight.app`, prints "Done".

Inspect the bundle:
```bash
ls -la build/VibeLight.app/Contents/
cat build/VibeLight.app/Contents/Info.plist
```

Should show: `MacOS/`, `Resources/`, `Info.plist`. Info.plist should have `LSUIElement=true` and `CFBundleExecutable=VibeLight`.

- [ ] **Step 3: Launch the .app**

```bash
open build/VibeLight.app
```

Expected:
- No Dock icon appears (LSUIElement working)
- Menubar shows the colored circle icon
- All menu items work as in `swift run` mode

If a Dock icon DOES appear, double-check Info.plist `LSUIElement` is `<true/>` not `<string>true</string>`.

- [ ] **Step 4: Create smoke test README**

`Resources/README-app-smoke.md`:

```markdown
# VibeLight.app — end-to-end smoke

After running `./scripts/bundle.sh`:

## 1. Launch

    open build/VibeLight.app

Expected: colored circle in menubar, no Dock icon, no warning dialog.

## 2. Check the menu

Click the circle. Should show:
- Status row (Idle / Working / …) and session count
- Sessions submenu
- Pause submenu (30 min / 1 hr / Until tomorrow)
- Test light effect submenu (7 states)
- Show Sessions Window…
- Settings… (placeholder)
- Quit VibeLight

## 3. Simulate hook events

    echo '{"session_id":"smoke1"}' | curl -s -X POST \
      -H 'Content-Type: application/json' --data-binary @- \
      'http://127.0.0.1:17345/event?hook=UserPromptSubmit'

Expected: icon turns blue (working) within 1 second.

    echo '{"session_id":"smoke1","message":"Claude needs your permission"}' | curl -s -X POST \
      -H 'Content-Type: application/json' --data-binary @- \
      'http://127.0.0.1:17345/event?hook=Notification'

Expected: icon turns red (needsAuth).

    echo '{"session_id":"smoke1"}' | curl -s -X POST \
      -H 'Content-Type: application/json' --data-binary @- \
      'http://127.0.0.1:17345/event?hook=Stop'

Expected: icon turns purple (done → idle).

## 4. Sessions window

Click "Show Sessions Window…". Open a second session via:

    echo '{"session_id":"smoke2","cwd":"/Users/me/projB"}' | curl -s -X POST \
      -H 'Content-Type: application/json' --data-binary @- \
      'http://127.0.0.1:17345/event?hook=UserPromptSubmit'

Expected: table updates within 1 second to show 2 rows.

## 5. Pause

Click Pause → "Pause for 30 minutes". The menu now shows "Paused until …" and a Resume button. Push a hook event — icon should still update (state tracking continues) but the HA light will NOT be called.

Click Resume; the next event resumes driving HA.

## 6. Test light effect

If you have a real HA-connected light, click Test light effect → Working. The light should turn blue and start breathing. Click another state to switch.

If you don't have HA, this is silent. Tests run in `swift test`.

## 7. Quit

Click Quit VibeLight. Process exits cleanly within 1 second. Verify:

    pgrep -f VibeLight   # should print nothing
```

- [ ] **Step 5: Commit**

```bash
git add scripts/bundle.sh Resources/README-app-smoke.md
git commit -m "feat(app): add bundle.sh and end-to-end .app smoke instructions"
```

---

## Final verification

- [ ] **Full test suite**

```bash
swift test
```

Expected: all tests pass. ~65 tests total (P1: 58 + P2: 7 new in Tasks 1–3).

- [ ] **Build the .app**

```bash
./scripts/bundle.sh
open build/VibeLight.app
```

Expected: menubar app launches, no Dock icon, menu works.

- [ ] **Walk through the smoke README**

Follow `Resources/README-app-smoke.md` steps 2–7. The light-affecting steps (Test light effect, Pause's silent-driver effect) need HA to fully verify; defer those until back home. Steps 2–4 (icon color changes, Sessions window) are HA-independent and should all work.

- [ ] **Tag P2 milestone**

```bash
git tag p2-app-shell
```

---

## P2 Done. What's next?

P2 produces a launchable .app:
- `./scripts/bundle.sh` → unsigned VibeLight.app
- Drag to `/Applications` or run from build dir
- Menubar icon reflects state; menu has Pause / Test / Sessions / Settings (placeholder) / Quit
- Sessions window opens separately
- Settings window is a placeholder pointing the user at JSON edits for now

**Open follow-ups carried into P3:**
- Real Settings UI (HA URL/token/light entity editor, mDNS HA discovery, Colors editor, Hook installer button, Scene pack mode toggle)
- Onboarding flow (7 steps from spec §6.3)
- HomeReachability (NWPathMonitor + HA `/api/` probe → menu shows "At home" / "Away")
- Scene pack driver + installer (spec §7.2.2)
- Hook installer (writes `~/.claude/hooks/vibelight.sh` and `~/.claude/settings.json`)
- Icon animations to match the actual light effect (breathing/blinking — currently the menubar circle is static)
- Code signing + notarization (Xcode project migration if needed)

**Next: P3 (Onboarding + Settings + Scene pack + Network).** Largest of the three plans, but most of the building blocks are already in place.
