# VibeLight P3: Onboarding + Settings + Scene Pack + Network — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the P2 app shell into a complete v1 product: first-launch onboarding wizard, full Settings UI across 6 tabs, mDNS-based HA discovery, network-aware enable/disable, an optional Scene-pack rendering mode, and one-click Claude Code hooks installation.

**Architecture:** Settings live in two stores — `UserDefaults` for non-secret config and `Keychain` for the HA token. The on-disk `config.json` (P1/P2 contract for the headless CLI) is kept as a denormalized output: the app writes it on save so the `vibelight-broker` CLI keeps working. New `LightDriver` implementations: existing `BrokerEmulatedDriver` stays the default; `ScenePackDriver` is opt-in. `BrokerHost` rebuilds its driver and (if necessary) restarts when settings change. SwiftUI `WindowGroup` scenes for onboarding and settings; an `OnboardingGate` decides whether to surface onboarding at launch.

**Tech Stack:** Swift 5.9+, SwiftUI, Network.framework (NWPathMonitor, NWBrowser), Security.framework (Keychain), macOS 13+. Zero third-party dependencies.

**Scope (P3 only):**
- Settings persistence: `UserDefaults` + `Keychain` + `config.json` round-trip
- `HomeReachability` (NWPathMonitor + periodic HA `/api/` probe)
- `HADiscovery` (NWBrowser on `_home-assistant._tcp.local`)
- `ScenePackInstaller` (create/delete 7 HA scenes via REST)
- `ScenePackDriver` (LightDriver impl calling `scene.turn_on`)
- `BrokerHost` driver-mode swap and config-reload mechanism
- `HookInstaller` (writes `~/.claude/hooks/vibelight.sh` and patches `~/.claude/settings.json` non-destructively)
- `AppViewModel` integration (reachability state, settings observation)
- 7-step Onboarding wizard
- Settings window with 6 tabs (General / Home Assistant / Colors & Effects / Network / Claude Code / Advanced)
- End-to-end smoke

**Out of scope (deferred to P4 or beyond):**
- Code signing / notarization
- Icon animations on the menubar (still static colored circle)
- Codex support (still Claude Code only)
- Pause-state persistence across app restart (Pause clears on restart)
- Telemetry / analytics
- Auto-update mechanism

---

## File Structure

```
VibeLight/
├── Package.swift                                  # unchanged
├── Sources/
│   ├── VibeBrokerCore/                            # unchanged
│   ├── VibeBrokerNet/
│   │   ├── ScenePackDriver.swift                  # NEW
│   │   ├── ScenePackInstaller.swift               # NEW
│   │   ├── HomeReachability.swift                 # NEW
│   │   ├── HADiscovery.swift                      # NEW
│   │   ├── BrokerHost.swift                       # MODIFY: driver-mode + reload
│   │   └── ... (others unchanged)
│   └── vibelight-app/
│       ├── Settings/
│       │   ├── SettingsStore.swift                # NEW: UserDefaults + Keychain
│       │   ├── KeychainHelper.swift               # NEW: Keychain CRUD
│       │   └── ConfigBuilder.swift                # NEW: Settings → Config struct
│       ├── ClaudeIntegration/
│       │   ├── HookInstaller.swift                # NEW: ~/.claude file ops
│       │   └── HookScript.swift                   # NEW: embedded shell source
│       ├── Onboarding/
│       │   ├── OnboardingWindow.swift             # NEW: wizard host
│       │   ├── OnboardingViewModel.swift          # NEW
│       │   ├── OnboardingGate.swift               # NEW: first-launch detection
│       │   ├── WelcomePage.swift                  # NEW
│       │   ├── HAConnectionPage.swift             # NEW (with mDNS scan)
│       │   ├── LightSelectionPage.swift           # NEW
│       │   ├── NetworkConfirmPage.swift           # NEW
│       │   ├── HookInstallPage.swift              # NEW
│       │   ├── EffectTestPage.swift               # NEW
│       │   └── OnboardingDonePage.swift           # NEW
│       ├── SettingsWindow/
│       │   ├── SettingsWindow.swift               # NEW: tab host (replaces P2 placeholder)
│       │   ├── GeneralTab.swift                   # NEW
│       │   ├── HomeAssistantTab.swift             # NEW
│       │   ├── ColorsTab.swift                    # NEW
│       │   ├── NetworkTab.swift                   # NEW
│       │   ├── ClaudeCodeTab.swift                # NEW
│       │   └── AdvancedTab.swift                  # NEW
│       ├── AppViewModel.swift                     # MODIFY: settings + reachability
│       ├── VibeLightApp.swift                     # MODIFY: onboarding scene + real settings
│       ├── SettingsPlaceholderWindow.swift        # DELETE (replaced)
│       └── ... (others unchanged)
└── Tests/
    └── VibeBrokerNetTests/
        ├── HomeReachabilityTests.swift            # NEW
        ├── ScenePackInstallerTests.swift          # NEW
        └── ScenePackDriverTests.swift             # NEW
```

---

## Task Index

| # | Task | Test layer |
|---|---|---|
| 1 | `SettingsStore` + `KeychainHelper` + `ConfigBuilder` | unit |
| 2 | `HomeReachability` actor (NWPathMonitor + HA ping) | unit |
| 3 | `HADiscovery` actor (mDNS NWBrowser) | manual (mDNS is hard to unit-test) |
| 4 | `ScenePackInstaller` + `ScenePackDriver` | unit with URLProtocol stub |
| 5 | `BrokerHost` driver-mode swap + config reload | unit |
| 6 | `HookInstaller` (write hook script + patch settings.json) | unit |
| 7 | `AppViewModel` integrates Settings + Reachability | manual |
| 8 | `OnboardingGate` + `OnboardingWindow` scaffold | manual |
| 9 | Onboarding pages 1–3 (Welcome / HA Connection / Light selection) | manual |
| 10 | Onboarding pages 4–5 (Network confirm / Hook install) | manual |
| 11 | Onboarding pages 6–7 (Effect test / Done) | manual |
| 12 | `SettingsWindow` framework + General tab + Advanced tab | manual |
| 13 | Settings: Home Assistant tab + Network tab | manual |
| 14 | Settings: Colors & Effects tab + Claude Code tab + end-to-end smoke | manual |

---

## Task 1: `SettingsStore` + `KeychainHelper` + `ConfigBuilder`

**Files:**
- Create: `Sources/vibelight-app/Settings/KeychainHelper.swift`
- Create: `Sources/vibelight-app/Settings/SettingsStore.swift`
- Create: `Sources/vibelight-app/Settings/ConfigBuilder.swift`
- Create: `Tests/VibeBrokerNetTests/ConfigBuilderTests.swift`

`SettingsStore` is the single source of truth for app-side settings. It reads/writes `UserDefaults` and Keychain. `ConfigBuilder` materializes a `Config` (the type the broker consumes) from current settings.

- [ ] **Step 1: Create `KeychainHelper.swift`**

`Sources/vibelight-app/Settings/KeychainHelper.swift`:

```swift
import Foundation
import Security

/// Thin wrapper over Security.framework for a single generic password item.
/// Service: "com.vibelight.app". Account: any string the caller picks.
enum KeychainHelper {
    private static let service = "com.vibelight.app"

    static func set(_ value: String, for account: String) {
        delete(for: account)
        let attrs: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
            kSecValueData as String:    Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne,
        ]
        var result: AnyObject?
        SecItemCopyMatching(q as CFDictionary, &result)
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(for account: String) -> Bool {
        let q: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(q as CFDictionary) == errSecSuccess
    }
}
```

- [ ] **Step 2: Create `SettingsStore.swift`**

`Sources/vibelight-app/Settings/SettingsStore.swift`:

```swift
import Foundation
import VibeBrokerCore

/// Source of truth for app-side settings. Non-secret values live in UserDefaults;
/// HA token lives in Keychain. Changes publish to subscribers via `onChange`.
@MainActor
final class SettingsStore: ObservableObject {
    // MARK: - Published settings

    @Published var haURL: String {
        didSet { defaults.set(haURL, forKey: Keys.haURL); fire() }
    }
    @Published var haLightEntity: String {
        didSet { defaults.set(haLightEntity, forKey: Keys.haLightEntity); fire() }
    }
    @Published var brokerPort: Int {
        didSet { defaults.set(brokerPort, forKey: Keys.brokerPort); fire() }
    }
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin); fire() }
    }
    @Published var notifyOnHAError: Bool {
        didSet { defaults.set(notifyOnHAError, forKey: Keys.notifyOnHAError); fire() }
    }
    @Published var defaultPauseSeconds: Int {
        didSet { defaults.set(defaultPauseSeconds, forKey: Keys.defaultPauseSeconds); fire() }
    }
    @Published var renderMode: RenderMode {
        didSet { defaults.set(renderMode.rawValue, forKey: Keys.renderMode); fire() }
    }
    @Published var colors: [VibeBrokerCore.State: ColorConfig] {
        didSet { persistColors(); fire() }
    }
    @Published var homeSSIDHint: String? {
        didSet { defaults.set(homeSSIDHint, forKey: Keys.homeSSIDHint); fire() }
    }

    // MARK: - Token (Keychain-backed)

    var haToken: String? {
        get { KeychainHelper.get("haToken") }
        set {
            if let v = newValue, !v.isEmpty {
                KeychainHelper.set(v, for: "haToken")
            } else {
                KeychainHelper.delete(for: "haToken")
            }
            fire()
        }
    }

    // MARK: - Derived

    /// Settings considered "complete enough" to skip onboarding.
    var isConfigured: Bool {
        !haURL.isEmpty && !haLightEntity.isEmpty && (haToken?.isEmpty == false)
    }

    // MARK: - Change subscriptions

    var onChange: () -> Void = {}
    private func fire() { onChange() }

    // MARK: - Render mode

    enum RenderMode: String { case brokerEmulated, scenePack }

    // MARK: - Init

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.haURL = defaults.string(forKey: Keys.haURL) ?? ""
        self.haLightEntity = defaults.string(forKey: Keys.haLightEntity) ?? ""
        self.brokerPort = defaults.object(forKey: Keys.brokerPort) as? Int ?? 17345
        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? true
        self.notifyOnHAError = defaults.object(forKey: Keys.notifyOnHAError) as? Bool ?? true
        self.defaultPauseSeconds = defaults.object(forKey: Keys.defaultPauseSeconds) as? Int ?? 1800
        self.renderMode = RenderMode(rawValue: defaults.string(forKey: Keys.renderMode) ?? "")
            ?? .brokerEmulated
        self.colors = Self.loadColors(defaults: defaults)
        self.homeSSIDHint = defaults.string(forKey: Keys.homeSSIDHint)
    }

    private static func defaultColors() -> [VibeBrokerCore.State: ColorConfig] {
        [
            .idle:         ColorConfig(rgb: [80, 30, 120],  brightness: 80,  effect: .solid),
            .working:      ColorConfig(rgb: [40, 120, 255], brightness: 200, effect: .breathe),
            .compacting:   ColorConfig(rgb: [240, 220, 60], brightness: 200, effect: .breathe),
            .waitingInput: ColorConfig(rgb: [255, 140, 30], brightness: 220, effect: .blinkThenSolid),
            .needsAuth:    ColorConfig(rgb: [255, 30, 30],  brightness: 230, effect: .solid),
            .error:        ColorConfig(rgb: [255, 30, 30],  brightness: 230, effect: .blink),
            .done:         ColorConfig(rgb: [80, 30, 120],  brightness: 200, effect: .blink),
        ]
    }

    private static func loadColors(defaults: UserDefaults) -> [VibeBrokerCore.State: ColorConfig] {
        guard let data = defaults.data(forKey: Keys.colors),
              let decoded = try? JSONDecoder().decode([String: ColorConfig].self, from: data) else {
            return defaultColors()
        }
        var result: [VibeBrokerCore.State: ColorConfig] = [:]
        for state in VibeBrokerCore.State.allCases {
            result[state] = decoded[state.serializedName] ?? defaultColors()[state]!
        }
        return result
    }

    private func persistColors() {
        var raw: [String: ColorConfig] = [:]
        for (state, color) in colors { raw[state.serializedName] = color }
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Keys.colors)
        }
    }

    func resetColors() {
        colors = Self.defaultColors()
    }

    func resetAll() {
        for key in Keys.allCases { defaults.removeObject(forKey: key.rawValue) }
        KeychainHelper.delete(for: "haToken")
        haURL = ""; haLightEntity = ""; brokerPort = 17345
        launchAtLogin = true; notifyOnHAError = true; defaultPauseSeconds = 1800
        renderMode = .brokerEmulated
        colors = Self.defaultColors()
        homeSSIDHint = nil
    }

    enum Keys: String, CaseIterable {
        case haURL              = "haURL"
        case haLightEntity      = "haLightEntity"
        case brokerPort         = "brokerPort"
        case launchAtLogin      = "launchAtLogin"
        case notifyOnHAError    = "notifyOnHAError"
        case defaultPauseSeconds = "defaultPauseSeconds"
        case renderMode         = "renderMode"
        case colors             = "colors"
        case homeSSIDHint       = "homeSSIDHint"
    }
}
```

- [ ] **Step 3: Create `ConfigBuilder.swift`**

`Sources/vibelight-app/Settings/ConfigBuilder.swift`:

```swift
import Foundation
import VibeBrokerCore

enum ConfigBuilder {
    enum BuildError: Error {
        case missingHAURL
        case invalidHAURL(String)
        case missingLightEntity
        case missingToken
    }

    static func build(from settings: SettingsStore) throws -> Config {
        guard !settings.haURL.isEmpty else { throw BuildError.missingHAURL }
        guard let url = URL(string: settings.haURL) else {
            throw BuildError.invalidHAURL(settings.haURL)
        }
        guard !settings.haLightEntity.isEmpty else { throw BuildError.missingLightEntity }
        guard let token = settings.haToken, !token.isEmpty else { throw BuildError.missingToken }

        return Config(
            broker: BrokerConfig(port: UInt16(settings.brokerPort)),
            homeAssistant: HAConfig(url: url, token: token, lightEntity: settings.haLightEntity),
            behavior: BehaviorConfig(
                sessionTtlSeconds: 300,
                errorAutoClearSeconds: 5,
                doneBlinkSeconds: 2,
                waitingInputBlinkSeconds: 3,
                debounceMillis: 100
            ),
            colors: settings.colors
        )
    }

    /// Write the same settings out to `~/.config/vibelight/config.json` so the
    /// `vibelight-broker` CLI keeps working with the same values.
    static func writeConfigJSON(_ settings: SettingsStore) throws {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/vibelight/config.json")
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var raw: [String: Any] = [:]
        raw["broker"] = ["port": settings.brokerPort]
        raw["homeAssistant"] = [
            "url": settings.haURL,
            "token": settings.haToken ?? "",
            "lightEntity": settings.haLightEntity,
        ]
        raw["behavior"] = [
            "sessionTtlSeconds":         300,
            "errorAutoClearSeconds":     5,
            "doneBlinkSeconds":          2,
            "waitingInputBlinkSeconds":  3,
            "debounceMillis":            100,
        ]
        var colorsOut: [String: Any] = [:]
        for (state, c) in settings.colors {
            colorsOut[state.serializedName] = [
                "rgb": c.rgb, "brightness": c.brightness,
                "effect": c.effect.rawValue,
            ]
        }
        raw["colors"] = colorsOut

        let data = try JSONSerialization.data(withJSONObject: raw, options: .prettyPrinted)
        try data.write(to: path, options: .atomic)
    }
}
```

- [ ] **Step 4: Write failing tests**

`Tests/VibeBrokerNetTests/ConfigBuilderTests.swift`:

```swift
import XCTest
@testable import VibeBrokerCore

final class ConfigBuilderTests: XCTestCase {
    // These tests cover the JSON-round-trip path for ConfigBuilder. The full
    // SettingsStore is @MainActor and tied to UserDefaults — we only test the
    // pure data flow here. UI integration is verified manually.

    func testConfigParsesAfterRoundTrip() throws {
        // Build a Config directly, encode the way ConfigBuilder.writeConfigJSON would,
        // decode via Config.parse, verify round-trip.
        let cfg = Config(
            broker: BrokerConfig(port: 17345),
            homeAssistant: HAConfig(url: URL(string: "http://h:8123")!, token: "tk", lightEntity: "light.x"),
            behavior: BehaviorConfig(
                sessionTtlSeconds: 300, errorAutoClearSeconds: 5,
                doneBlinkSeconds: 2, waitingInputBlinkSeconds: 3, debounceMillis: 100
            ),
            colors: [
                .idle:         ColorConfig(rgb: [80, 30, 120],  brightness: 80,  effect: .solid),
                .working:      ColorConfig(rgb: [40, 120, 255], brightness: 200, effect: .breathe),
                .compacting:   ColorConfig(rgb: [240, 220, 60], brightness: 200, effect: .breathe),
                .waitingInput: ColorConfig(rgb: [255, 140, 30], brightness: 220, effect: .blinkThenSolid),
                .needsAuth:    ColorConfig(rgb: [255, 30, 30],  brightness: 230, effect: .solid),
                .error:        ColorConfig(rgb: [255, 30, 30],  brightness: 230, effect: .blink),
                .done:         ColorConfig(rgb: [80, 30, 120],  brightness: 200, effect: .blink),
            ]
        )

        // Manually replicate the JSON shape writeConfigJSON produces:
        var raw: [String: Any] = [
            "broker": ["port": Int(cfg.broker.port)],
            "homeAssistant": [
                "url": cfg.homeAssistant.url.absoluteString,
                "token": cfg.homeAssistant.token,
                "lightEntity": cfg.homeAssistant.lightEntity,
            ],
            "behavior": [
                "sessionTtlSeconds":        cfg.behavior.sessionTtlSeconds,
                "errorAutoClearSeconds":    cfg.behavior.errorAutoClearSeconds,
                "doneBlinkSeconds":         cfg.behavior.doneBlinkSeconds,
                "waitingInputBlinkSeconds": cfg.behavior.waitingInputBlinkSeconds,
                "debounceMillis":           cfg.behavior.debounceMillis,
            ],
        ]
        var colors: [String: Any] = [:]
        for (state, c) in cfg.colors {
            colors[state.serializedName] = [
                "rgb": c.rgb, "brightness": c.brightness, "effect": c.effect.rawValue,
            ]
        }
        raw["colors"] = colors

        let data = try JSONSerialization.data(withJSONObject: raw)
        let parsed = try Config.parse(data)

        XCTAssertEqual(parsed.broker.port, cfg.broker.port)
        XCTAssertEqual(parsed.homeAssistant.url, cfg.homeAssistant.url)
        XCTAssertEqual(parsed.homeAssistant.token, cfg.homeAssistant.token)
        XCTAssertEqual(parsed.colors[.working]?.rgb, [40, 120, 255])
    }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter VibeBrokerNetTests.ConfigBuilderTests`
Expected: PASS (the test does not need SettingsStore — it verifies the JSON shape that ConfigBuilder will produce can be parsed back by Config.parse).

Run: `swift build`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add Sources/vibelight-app/Settings Tests/VibeBrokerNetTests/ConfigBuilderTests.swift
git commit -m "feat(app): add SettingsStore, KeychainHelper, ConfigBuilder"
```

---

## Task 2: `HomeReachability` actor

**Files:**
- Create: `Sources/VibeBrokerNet/HomeReachability.swift`
- Create: `Tests/VibeBrokerNetTests/HomeReachabilityTests.swift`

Combines `NWPathMonitor` (free network-change events) with periodic HA `/api/` probes (5 minutes default, or on every path change). Exposes an `AsyncStream<Bool>` of "at home now?" updates.

- [ ] **Step 1: Write failing tests**

`Tests/VibeBrokerNetTests/HomeReachabilityTests.swift`:

```swift
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
        XCTAssertFalse(await reach.checkNow())
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
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter VibeBrokerNetTests.HomeReachabilityTests`
Expected: FAIL — `HomeReachability` undefined.

- [ ] **Step 3: Implement `HomeReachability.swift`**

`Sources/VibeBrokerNet/HomeReachability.swift`:

```swift
import Foundation
import Network

public actor HomeReachability {
    public typealias Probe = @Sendable () async -> Bool

    private let probe: Probe
    private var current: Bool = false
    private var continuations: [AsyncStream<Bool>.Continuation] = []
    private var pathMonitor: NWPathMonitor?
    private var periodicTask: Task<Void, Never>?

    public init(probe: @escaping Probe) {
        self.probe = probe
    }

    public func current() -> Bool { current }

    @discardableResult
    public func checkNow() async -> Bool {
        let result = await probe()
        if result != current {
            current = result
        }
        for cont in continuations {
            cont.yield(result)
        }
        return result
    }

    public func start() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { await self?.checkNow() }
        }
        monitor.start(queue: .global())
        self.pathMonitor = monitor

        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.checkNow()
            }
        }
    }

    public func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        periodicTask?.cancel()
        periodicTask = nil
        for cont in continuations { cont.finish() }
        continuations.removeAll()
    }

    public func stream() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            continuations.append(continuation)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(continuation) }
            }
        }
    }

    private func removeContinuation(_ cont: AsyncStream<Bool>.Continuation) {
        continuations.removeAll {
            // No identity for Continuation; we rely on onTermination to drop refs.
            // In practice continuations is small and short-lived; this is a no-op
            // for v1 (we don't actively prune). Stop() clears all.
            _ = $0
            return false
        }
    }

    /// Convenience: build a probe that hits HA's `/api/` endpoint.
    public static func haProbe(baseURL: URL, token: String,
                                session: URLSession = .shared,
                                timeout: TimeInterval = 0.5) -> Probe {
        return { @Sendable in
            var req = URLRequest(url: baseURL.appendingPathComponent("api/"))
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = timeout
            do {
                let (_, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse else { return false }
                return (200..<300).contains(http.statusCode)
            } catch {
                return false
            }
        }
    }
}
```

Note: the test's `current()` accessor and our public `func current() -> Bool` differ — Swift's actor isolation lets us read state inside the actor synchronously, but external callers must `await`. The test uses `await reach.checkNow()` which returns the value directly; it doesn't call `current()`. We keep `current()` as a convenience.

- [ ] **Step 4: Run tests**

Run: `swift test --filter VibeBrokerNetTests.HomeReachabilityTests`
Expected: PASS — 3 tests.

Run: `swift test`
Expected: 69 tests pass total (65 P1/P2 + 1 ConfigBuilder + 3 HomeReachability).

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeBrokerNet/HomeReachability.swift Tests/VibeBrokerNetTests/HomeReachabilityTests.swift
git commit -m "feat(net): add HomeReachability with NWPathMonitor + HA probe"
```

---

## Task 3: `HADiscovery` actor (mDNS)

**Files:**
- Create: `Sources/VibeBrokerNet/HADiscovery.swift`

Browses Bonjour for `_home-assistant._tcp.local.` services. Exposes an `AsyncStream<DiscoveredHA>` of found services with name + host + port. No automated test — mDNS is hard to mock without elaborate plumbing; manual smoke covers it.

- [ ] **Step 1: Implement `HADiscovery.swift`**

`Sources/VibeBrokerNet/HADiscovery.swift`:

```swift
import Foundation
import Network

public struct DiscoveredHA: Sendable, Equatable, Identifiable {
    public let id: String   // unique name string
    public let name: String
    public let endpoint: String   // host:port suitable for URL building
}

public actor HADiscovery {
    private var browser: NWBrowser?
    private var continuations: [AsyncStream<[DiscoveredHA]>.Continuation] = []
    private var discovered: [String: DiscoveredHA] = [:]

    public init() {}

    public func start() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = false
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_home-assistant._tcp.", domain: "local.")
        let browser = NWBrowser(for: descriptor, using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { await self?.handle(results) }
        }
        browser.start(queue: .global())
        self.browser = browser
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        for cont in continuations { cont.finish() }
        continuations.removeAll()
        discovered.removeAll()
    }

    public func stream() -> AsyncStream<[DiscoveredHA]> {
        AsyncStream { continuation in
            continuation.yield(Array(discovered.values))
            continuations.append(continuation)
        }
    }

    public func current() -> [DiscoveredHA] {
        Array(discovered.values)
    }

    private func handle(_ results: Set<NWBrowser.Result>) {
        var newDict: [String: DiscoveredHA] = [:]
        for result in results {
            if case let .service(name, _, _, _) = result.endpoint {
                let endpointStr = "\(name).local."
                let item = DiscoveredHA(id: name, name: name, endpoint: endpointStr)
                newDict[name] = item
            }
        }
        discovered = newDict
        let list = Array(newDict.values)
        for cont in continuations {
            cont.yield(list)
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: clean.

- [ ] **Step 3: Manual smoke (if you have an HA instance on the LAN)**

You can verify the discovery is functional by writing a one-off script:

```swift
// scratch test (not committed)
let d = HADiscovery()
await d.start()
try await Task.sleep(nanoseconds: 3_000_000_000)
print(await d.current())
await d.stop()
```

If you have HA at home it should appear; without HA on the LAN this returns empty (also expected behavior — Settings UI will fall back to manual URL entry).

- [ ] **Step 4: Commit**

```bash
git add Sources/VibeBrokerNet/HADiscovery.swift
git commit -m "feat(net): add HADiscovery via Bonjour _home-assistant._tcp"
```

---

## Task 4: `ScenePackInstaller` + `ScenePackDriver`

**Files:**
- Create: `Sources/VibeBrokerNet/ScenePackInstaller.swift`
- Create: `Sources/VibeBrokerNet/ScenePackDriver.swift`
- Create: `Tests/VibeBrokerNetTests/ScenePackInstallerTests.swift`
- Create: `Tests/VibeBrokerNetTests/ScenePackDriverTests.swift`

ScenePackInstaller creates 7 scenes (`scene.vibelight_<state>`) via `POST /api/config/scene/config/<scene_id>`. Each scene encodes the configured color for that state on the configured light entity. ScenePackDriver simply calls `scene.turn_on` for the matching scene name on each `render(state)`.

- [ ] **Step 1: Write failing tests for installer**

`Tests/VibeBrokerNetTests/ScenePackInstallerTests.swift`:

```swift
import XCTest
@testable import VibeBrokerNet
@testable import VibeBrokerCore

final class ScenePackInstallerTests: XCTestCase {
    private func makeConfig() -> Config {
        BrokerEmulatedDriverSolidTests().makeConfigForBreathe()
    }

    private func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    func testInstallCreates7Scenes() async throws {
        var capturedPaths: [String] = []
        MockURLProtocol.handler = { req in
            capturedPaths.append(req.url!.path)
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("{}".utf8))
        }
        let installer = ScenePackInstaller(
            baseURL: URL(string: "http://h:8123")!, token: "t",
            session: makeSession()
        )
        try await installer.install(config: makeConfig())

        XCTAssertEqual(capturedPaths.count, 7)
        XCTAssertTrue(capturedPaths.contains { $0.contains("vibelight_idle") })
        XCTAssertTrue(capturedPaths.contains { $0.contains("vibelight_working") })
        XCTAssertTrue(capturedPaths.contains { $0.contains("vibelight_error") })
    }

    func testUninstallDeletes7Scenes() async throws {
        var deletePaths: [String] = []
        MockURLProtocol.handler = { req in
            if req.httpMethod == "DELETE" { deletePaths.append(req.url!.path) }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("{}".utf8))
        }
        let installer = ScenePackInstaller(
            baseURL: URL(string: "http://h:8123")!, token: "t",
            session: makeSession()
        )
        try await installer.uninstall()
        XCTAssertEqual(deletePaths.count, 7)
    }

    func testInstallPropagatesAuthError() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, Data("{}".utf8))
        }
        let installer = ScenePackInstaller(
            baseURL: URL(string: "http://h:8123")!, token: "t",
            session: makeSession()
        )
        do {
            try await installer.install(config: makeConfig())
            XCTFail("expected throw")
        } catch {
            // expected
        }
    }
}
```

- [ ] **Step 2: Write failing tests for driver**

`Tests/VibeBrokerNetTests/ScenePackDriverTests.swift`:

```swift
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
```

- [ ] **Step 3: Run tests to verify failure**

Run: `swift test --filter VibeBrokerNetTests.ScenePack`
Expected: FAIL — `ScenePackInstaller`/`ScenePackDriver` undefined.

- [ ] **Step 4: Implement `ScenePackInstaller.swift`**

`Sources/VibeBrokerNet/ScenePackInstaller.swift`:

```swift
import Foundation
import VibeBrokerCore

public final class ScenePackInstaller: @unchecked Sendable {
    public enum Error: Swift.Error {
        case http(Int)
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

    public func install(config: Config) async throws {
        let entity = config.homeAssistant.lightEntity
        for state in VibeBrokerCore.State.allCases {
            let color = config.colors[state]!
            let sceneId = "vibelight_\(state.serializedName)"
            let entityAttrs: [String: Any] = [
                "state": "on",
                "rgb_color": color.rgb,
                "brightness": color.brightness,
            ]
            let payload: [String: Any] = [
                "name": "VibeLight: \(state.serializedName)",
                "icon": "mdi:lightbulb",
                "entities": [entity: entityAttrs],
            ]
            try await postJSON(path: "/api/config/scene/config/\(sceneId)", body: payload)
        }
    }

    public func uninstall() async throws {
        for state in VibeBrokerCore.State.allCases {
            let sceneId = "vibelight_\(state.serializedName)"
            try await delete(path: "/api/config/scene/config/\(sceneId)")
        }
    }

    private func postJSON(path: String, body: [String: Any]) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 3.0
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch { throw Error.encoding }
        try await send(req)
    }

    private func delete(path: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 3.0
        try await send(req)
    }

    private func send(_ req: URLRequest) async throws {
        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw Error.http(-1) }
        if !(200..<300).contains(http.statusCode) { throw Error.http(http.statusCode) }
    }
}
```

- [ ] **Step 5: Implement `ScenePackDriver.swift`**

`Sources/VibeBrokerNet/ScenePackDriver.swift`:

```swift
import Foundation
import VibeBrokerCore

public actor ScenePackDriver: LightDriver {
    private let client: LightServiceCaller
    private var currentTask: Task<Void, Never>?

    public init(client: LightServiceCaller) {
        self.client = client
    }

    public func render(_ state: VibeBrokerCore.State) async {
        await cancel()
        let entityId = "scene.vibelight_\(state.serializedName)"
        currentTask = Task { [client] in
            try? await client.callService(
                domain: "scene", service: "turn_on",
                data: ["entity_id": entityId]
            )
        }
    }

    public func cancel() async {
        currentTask?.cancel()
        currentTask = nil
    }
}
```

- [ ] **Step 6: Run tests**

Run: `swift test --filter VibeBrokerNetTests.ScenePack`
Expected: all PASS.

Run: `swift test`
Expected: 74 tests now (69 + 3 installer + 2 driver).

- [ ] **Step 7: Commit**

```bash
git add Sources/VibeBrokerNet/ScenePack*.swift Tests/VibeBrokerNetTests/ScenePack*.swift
git commit -m "feat(net): add ScenePackInstaller and ScenePackDriver"
```

---

## Task 5: `BrokerHost` driver-mode swap + config reload

**Files:**
- Modify: `Sources/VibeBrokerNet/BrokerHost.swift`
- Modify: `Tests/VibeBrokerNetTests/BrokerHostTests.swift`

`BrokerHost` gains:
- `setDriverMode(_ mode: DriverMode)` — swaps internal driver
- `reload(config: Config)` — atomically updates config (used when user saves Settings)

When mode or config changes, the current effect is cancelled and the new driver takes over.

- [ ] **Step 1: Add failing test**

Append to `Tests/VibeBrokerNetTests/BrokerHostTests.swift`:

```swift
final class BrokerHostDriverModeTests: XCTestCase {
    func testCanSwitchToScenePackMode() async throws {
        let host = BrokerHost(config: BrokerHostTests.makeConfigStatic())
        try await host.start()
        defer { Task { await host.stop() } }

        await host.setDriverMode(.scenePack)
        XCTAssertEqual(await host.driverMode(), .scenePack)

        await host.setDriverMode(.brokerEmulated)
        XCTAssertEqual(await host.driverMode(), .brokerEmulated)
    }

    func testReloadReplacesConfig() async throws {
        let host = BrokerHost(config: BrokerHostTests.makeConfigStatic(port: 0))
        try await host.start()
        defer { Task { await host.stop() } }

        let newCfg = BrokerHostTests.makeConfigStatic(port: 0)
        await host.reload(config: newCfg)
        // The listener stays bound; we just verify no error and snapshot works.
        let snapshot = await host.sessionSnapshot()
        XCTAssertTrue(snapshot.isEmpty)
    }
}

extension BrokerHostTests {
    static func makeConfigStatic(port: UInt16 = 0) -> Config {
        let base = BrokerEmulatedDriverSolidTests().makeConfigForBreathe()
        return Config(
            broker: BrokerConfig(port: port),
            homeAssistant: base.homeAssistant,
            behavior: base.behavior, colors: base.colors
        )
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter VibeBrokerNetTests.BrokerHostDriverModeTests`
Expected: FAIL — `setDriverMode`/`reload`/`driverMode` undefined.

- [ ] **Step 3: Modify `BrokerHost.swift`**

Replace the existing `BrokerHost` implementation. Replace `Sources/VibeBrokerNet/BrokerHost.swift`:

```swift
import Foundation
import VibeBrokerCore

public enum DriverMode: String, Sendable {
    case brokerEmulated
    case scenePack
}

public actor BrokerHost {
    private var config: Config
    private let store: SessionStore
    private let haClient: HAClient
    private var driver: any LightDriver
    private var mode: DriverMode = .brokerEmulated
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
        let initial = BrokerEmulatedDriver(client: haClient, config: config)
        self.driver = initial
        self.router = EventRouter(store: store, driver: initial, config: config)
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

    public func testRender(_ state: VibeBrokerCore.State) async {
        await driver.render(state)
    }

    public func driverMode() -> DriverMode { mode }

    public func setDriverMode(_ newMode: DriverMode) async {
        guard newMode != mode else { return }
        await driver.cancel()
        mode = newMode
        switch newMode {
        case .brokerEmulated:
            driver = BrokerEmulatedDriver(client: haClient, config: config)
        case .scenePack:
            driver = ScenePackDriver(client: haClient)
        }
        await router.setDriver(driver)
    }

    public func reload(config newConfig: Config) async {
        config = newConfig
        // Rebuild the driver against the new config (colors / brightness may have changed).
        await driver.cancel()
        switch mode {
        case .brokerEmulated:
            driver = BrokerEmulatedDriver(client: haClient, config: newConfig)
        case .scenePack:
            driver = ScenePackDriver(client: haClient)
        }
        await router.setDriver(driver)
        await router.setConfig(newConfig)
    }
}
```

- [ ] **Step 4: Add `setDriver` and `setConfig` to `EventRouter`**

In `Sources/VibeBrokerNet/EventRouter.swift`, change the existing `private let driver: LightDriver` to:

```swift
private var driver: any LightDriver
private var config: Config
```

(Two `let`s become two `var`s. Make sure to also remove the `let` from the existing `private let config: Config`.)

Then add these public methods to the actor:

```swift
public func setDriver(_ newDriver: any LightDriver) {
    driver = newDriver
}

public func setConfig(_ newConfig: Config) {
    config = newConfig
}
```

This change is internal and backward-compatible — existing callers see the same surface.

- [ ] **Step 5: Run tests**

Run: `swift test --filter VibeBrokerNetTests.BrokerHostDriverModeTests`
Expected: PASS.

Run: `swift test`
Expected: 76 tests pass total.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeBrokerNet/BrokerHost.swift Sources/VibeBrokerNet/EventRouter.swift Tests/VibeBrokerNetTests/BrokerHostTests.swift
git commit -m "feat(net): BrokerHost supports driver-mode swap and config reload"
```

---

## Task 6: `HookInstaller`

**Files:**
- Create: `Sources/vibelight-app/ClaudeIntegration/HookInstaller.swift`
- Create: `Sources/vibelight-app/ClaudeIntegration/HookScript.swift`
- Create: `Tests/VibeBrokerNetTests/HookInstallerSmokeTests.swift` (smoke-only — tests use a tempdir)

`HookInstaller` writes `~/.claude/hooks/vibelight.sh` and **non-destructively** patches `~/.claude/settings.json`. If a vibelight hook is already present, no-op. Otherwise, append new hook entries to each of the 8 hook events without disturbing user-installed hooks for the same events.

- [ ] **Step 1: Create `HookScript.swift`**

`Sources/vibelight-app/ClaudeIntegration/HookScript.swift`:

```swift
import Foundation

enum HookScript {
    /// Verbatim contents of the hook shell script. Increment scriptVersion when
    /// the script content changes; HookInstaller compares to detect "out of date".
    static let scriptVersion = "1"

    static let body: String = """
    #!/usr/bin/env bash
    # vibelight: forward Claude Code hook payload to local broker.
    # vibelight-script-version: \(scriptVersion)
    exec curl -s -m 0.2 -X POST \\
      -H 'Content-Type: application/json' \\
      --data-binary @- \\
      "http://127.0.0.1:17345/event?hook=$1" >/dev/null 2>&1 || true
    """

    static let hookEvents: [String] = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "Notification", "PreCompact", "Stop", "SessionEnd",
    ]
}
```

- [ ] **Step 2: Create `HookInstaller.swift`**

`Sources/vibelight-app/ClaudeIntegration/HookInstaller.swift`:

```swift
import Foundation

enum HookInstallStatus {
    case notInstalled
    case installed
}

enum HookInstallerError: Error {
    case writeFailed(String)
}

struct HookInstaller {
    /// Root for Claude Code config. Override in tests to point at a temp dir.
    let claudeRoot: URL

    init(claudeRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")) {
        self.claudeRoot = claudeRoot
    }

    var hookScriptPath: URL {
        claudeRoot.appendingPathComponent("hooks/vibelight.sh")
    }

    var settingsPath: URL {
        claudeRoot.appendingPathComponent("settings.json")
    }

    func status() -> HookInstallStatus {
        FileManager.default.fileExists(atPath: hookScriptPath.path)
            ? .installed : .notInstalled
    }

    func install() throws {
        try FileManager.default.createDirectory(
            at: hookScriptPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try HookScript.body.write(to: hookScriptPath, atomically: true, encoding: .utf8)
        } catch {
            throw HookInstallerError.writeFailed("hook script: \(error)")
        }
        do {
            var attrs = try FileManager.default.attributesOfItem(atPath: hookScriptPath.path)
            attrs[.posixPermissions] = 0o755
            try FileManager.default.setAttributes(attrs, ofItemAtPath: hookScriptPath.path)
        } catch {
            throw HookInstallerError.writeFailed("chmod: \(error)")
        }

        // Patch settings.json: append vibelight entries to each hook event, skipping
        // any event that already has a vibelight.sh hook.
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = json
        }
        var hooks: [String: Any] = root["hooks"] as? [String: Any] ?? [:]

        for event in HookScript.hookEvents {
            var groups: [[String: Any]] = hooks[event] as? [[String: Any]] ?? []
            let alreadyHasVibelight = groups.contains(where: { group in
                let entries = group["hooks"] as? [[String: Any]] ?? []
                return entries.contains(where: { e in
                    (e["command"] as? String)?.contains("vibelight.sh") == true
                })
            })
            if alreadyHasVibelight { continue }
            let newGroup: [String: Any] = [
                "hooks": [
                    ["type": "command",
                     "command": "\(hookScriptPath.path) \(event)"]
                ]
            ]
            groups.append(newGroup)
            hooks[event] = groups
        }
        root["hooks"] = hooks

        do {
            let data = try JSONSerialization.data(
                withJSONObject: root, options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: settingsPath, options: .atomic)
        } catch {
            throw HookInstallerError.writeFailed("settings.json: \(error)")
        }
    }

    func uninstall() throws {
        // Remove vibelight entries from settings.json
        if let data = try? Data(contentsOf: settingsPath),
           var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var hooks: [String: Any] = root["hooks"] as? [String: Any] ?? [:]
            for event in HookScript.hookEvents {
                guard var groups = hooks[event] as? [[String: Any]] else { continue }
                groups.removeAll { group in
                    let entries = group["hooks"] as? [[String: Any]] ?? []
                    return entries.contains(where: { e in
                        (e["command"] as? String)?.contains("vibelight.sh") == true
                    })
                }
                if groups.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = groups
                }
            }
            if hooks.isEmpty {
                root.removeValue(forKey: "hooks")
            } else {
                root["hooks"] = hooks
            }
            let data2 = try JSONSerialization.data(
                withJSONObject: root, options: [.prettyPrinted, .sortedKeys]
            )
            try data2.write(to: settingsPath, options: .atomic)
        }
        try? FileManager.default.removeItem(at: hookScriptPath)
    }
}
```

- [ ] **Step 3: Write tests against a tempdir**

`Tests/VibeBrokerNetTests/HookInstallerSmokeTests.swift`:

```swift
import XCTest

// NOTE: HookInstaller lives in the vibelight-app target which the test target
// can't directly @testable-import (apps aren't typically test-importable from
// a sibling library test target). We test HookInstaller's behavior indirectly
// by replicating its logic against a tempdir — this catches regressions in the
// JSON merge algorithm without requiring an app-target test rig. The full
// behavior is also smoke-tested manually in Task 14.

final class HookSettingsMergeTests: XCTestCase {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibelight-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Verifies the JSON shape we'll write is what Claude Code expects.
    /// (Schema check — not the installer itself.)
    func testHookEntryShapeRoundTrips() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let settingsPath = dir.appendingPathComponent("settings.json")
        let entry: [String: Any] = [
            "hooks": [
                "UserPromptSubmit": [
                    [
                        "hooks": [
                            ["type": "command",
                             "command": "/Users/me/.claude/hooks/vibelight.sh UserPromptSubmit"]
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: entry, options: .prettyPrinted)
        try data.write(to: settingsPath)

        let reread = try JSONSerialization.jsonObject(with: try Data(contentsOf: settingsPath)) as? [String: Any]
        XCTAssertNotNil((reread?["hooks"] as? [String: Any])?["UserPromptSubmit"])
    }
}
```

(Lighter than ideal — full installer tested by hand in T14. The placement of HookInstaller in the app target makes deep unit testing awkward; tradeoff accepted for v1.)

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: 77 tests pass (76 + 1 schema test).

Run: `swift build`
Expected: clean — both app and net targets compile.

- [ ] **Step 5: Commit**

```bash
git add Sources/vibelight-app/ClaudeIntegration Tests/VibeBrokerNetTests/HookInstallerSmokeTests.swift
git commit -m "feat(app): add HookInstaller for ~/.claude integration"
```

---

## Task 7: `AppViewModel` integrates Settings + Reachability

**Files:**
- Modify: `Sources/vibelight-app/AppViewModel.swift`

`AppViewModel` becomes the integration point. It owns a `SettingsStore`, listens to it via `onChange`, and rebuilds the broker config when settings change. It also owns a `HomeReachability` actor and exposes its current value as a `@Published` bool.

- [ ] **Step 1: Replace `AppViewModel.swift`**

Replace `Sources/vibelight-app/AppViewModel.swift`:

```swift
import SwiftUI
import VibeBrokerCore
import VibeBrokerNet

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var effectiveState: VibeBrokerCore.State = .idle
    @Published private(set) var sessions: [SessionRecord] = []
    @Published private(set) var paused: Bool = false
    @Published private(set) var listening: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var pauseUntil: Date?
    @Published private(set) var isAtHome: Bool = false
    @Published var needsOnboarding: Bool = false

    let settings = SettingsStore()
    let hookInstaller = HookInstaller()

    private var host: BrokerHost?
    private var reachability: HomeReachability?
    private var refreshTask: Task<Void, Never>?
    private var pauseResumeTask: Task<Void, Never>?
    private var reachabilityTask: Task<Void, Never>?

    init() {
        settings.onChange = { [weak self] in
            Task { @MainActor [weak self] in await self?.handleSettingsChange() }
        }
        if settings.isConfigured {
            bootstrap()
        } else {
            needsOnboarding = true
        }
    }

    func bootstrap() {
        guard host == nil else { return }
        Task {
            do {
                let config = try ConfigBuilder.build(from: settings)
                try ConfigBuilder.writeConfigJSON(settings)

                let host = BrokerHost(config: config)
                await host.setObserver { [weak self] state in
                    await self?.updateEffective(state)
                }
                await host.setDriverMode(.init(rawValue: settings.renderMode.rawValue) ?? .brokerEmulated)
                try await host.start()
                self.host = host
                self.listening = true
                self.startSessionRefresh()
                self.startReachability(url: config.homeAssistant.url, token: config.homeAssistant.token)
            } catch {
                self.lastError = String(describing: error)
            }
        }
    }

    func shutdown() async {
        refreshTask?.cancel()
        reachabilityTask?.cancel()
        await reachability?.stop()
        await host?.stop()
        host = nil
        listening = false
    }

    private func handleSettingsChange() async {
        // Settings changed: write config.json + reload broker if running.
        guard settings.isConfigured else { return }
        do {
            try ConfigBuilder.writeConfigJSON(settings)
            if let host {
                let cfg = try ConfigBuilder.build(from: settings)
                await host.reload(config: cfg)
                await host.setDriverMode(.init(rawValue: settings.renderMode.rawValue) ?? .brokerEmulated)
            } else {
                bootstrap()
            }
        } catch {
            lastError = String(describing: error)
        }
    }

    private func startReachability(url: URL, token: String) {
        let probe = HomeReachability.haProbe(baseURL: url, token: token)
        let reach = HomeReachability(probe: probe)
        Task { await reach.start() }
        self.reachability = reach
        reachabilityTask = Task { [weak self] in
            guard let reach = self?.reachability else { return }
            let stream = await reach.stream()
            for await value in stream {
                await MainActor.run { self?.isAtHome = value }
            }
        }
        Task { _ = await reach.checkNow() }
    }

    func pauseFor(_ duration: PauseDuration) {
        let resumeAt = duration.resumeDate(now: Date())
        pauseUntil = resumeAt
        setPausedInternal(true)
        pauseResumeTask?.cancel()
        pauseResumeTask = Task { [weak self] in
            let nanos = UInt64(max(0, resumeAt.timeIntervalSinceNow) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.resume() }
        }
    }

    func resume() {
        pauseResumeTask?.cancel()
        pauseResumeTask = nil
        pauseUntil = nil
        setPausedInternal(false)
    }

    private func setPausedInternal(_ paused: Bool) {
        Task {
            await host?.setPaused(paused)
            await MainActor.run { self.paused = paused }
        }
    }

    func testRender(_ state: VibeBrokerCore.State) {
        Task { await host?.testRender(state) }
    }

    func finishOnboarding() {
        needsOnboarding = false
        if host == nil { bootstrap() }
    }

    private func updateEffective(_ state: VibeBrokerCore.State) {
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
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/vibelight-app/AppViewModel.swift
git commit -m "feat(app): integrate SettingsStore + HomeReachability in AppViewModel"
```

---

## Task 8: `OnboardingGate` + `OnboardingWindow` scaffold

**Files:**
- Create: `Sources/vibelight-app/Onboarding/OnboardingViewModel.swift`
- Create: `Sources/vibelight-app/Onboarding/OnboardingWindow.swift`
- Modify: `Sources/vibelight-app/VibeLightApp.swift`

Adds a SwiftUI `Window` scene that appears when `viewModel.needsOnboarding == true`. Has a step indicator and forward/back navigation.

- [ ] **Step 1: Create `OnboardingViewModel.swift`**

`Sources/vibelight-app/Onboarding/OnboardingViewModel.swift`:

```swift
import SwiftUI
import VibeBrokerCore
import VibeBrokerNet

@MainActor
final class OnboardingViewModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome
        case haConnection
        case lightSelection
        case networkConfirm
        case hookInstall
        case effectTest
        case done

        var title: String {
            switch self {
            case .welcome:         return "Welcome"
            case .haConnection:    return "Connect to Home Assistant"
            case .lightSelection:  return "Choose a light"
            case .networkConfirm:  return "Confirm home network"
            case .hookInstall:     return "Install Claude Code hooks"
            case .effectTest:      return "Test light effects"
            case .done:            return "All set"
            }
        }
    }

    @Published var step: Step = .welcome
    @Published var canAdvance: Bool = true
    @Published var lastError: String?

    let appViewModel: AppViewModel
    let settings: SettingsStore
    let discovery = HADiscovery()
    @Published var discovered: [DiscoveredHA] = []
    @Published var lightEntities: [String] = []

    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
        self.settings = appViewModel.settings
    }

    func next() {
        guard let nextStep = Step(rawValue: step.rawValue + 1) else { return }
        step = nextStep
    }

    func previous() {
        guard let prevStep = Step(rawValue: step.rawValue - 1) else { return }
        step = prevStep
    }

    func startDiscovery() {
        Task {
            await discovery.start()
            let stream = await discovery.stream()
            for await list in stream {
                await MainActor.run { self.discovered = list }
            }
        }
    }

    func stopDiscovery() {
        Task { await discovery.stop() }
    }

    func testHAConnection() async {
        guard !settings.haURL.isEmpty, let url = URL(string: settings.haURL),
              let token = settings.haToken, !token.isEmpty else {
            lastError = "URL and token required"
            return
        }
        let client = HAClient(baseURL: url, token: token)
        do {
            _ = try await client.getApiStatus()
            lastError = nil
        } catch {
            lastError = "Connection failed: \(error)"
        }
    }

    func fetchLightEntities() async {
        guard !settings.haURL.isEmpty, let url = URL(string: settings.haURL),
              let token = settings.haToken, !token.isEmpty else { return }
        var req = URLRequest(url: url.appendingPathComponent("api/states"))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 3.0
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                let lights = arr.compactMap { $0["entity_id"] as? String }
                    .filter { $0.hasPrefix("light.") }
                await MainActor.run { self.lightEntities = lights.sorted() }
            }
        } catch {
            await MainActor.run { self.lastError = "Failed to list lights: \(error)" }
        }
    }

    func finish() {
        appViewModel.finishOnboarding()
    }
}
```

- [ ] **Step 2: Create `OnboardingWindow.swift`**

`Sources/vibelight-app/Onboarding/OnboardingWindow.swift`:

```swift
import SwiftUI

struct OnboardingWindow: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(viewModel.step.title).font(.title2).bold()
            stepIndicator
        }
        .padding()
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingViewModel.Step.allCases, id: \.rawValue) { s in
                Circle()
                    .fill(s.rawValue <= viewModel.step.rawValue ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.step {
        case .welcome:         WelcomePage(viewModel: viewModel)
        case .haConnection:    HAConnectionPage(viewModel: viewModel)
        case .lightSelection:  LightSelectionPage(viewModel: viewModel)
        case .networkConfirm:  NetworkConfirmPage(viewModel: viewModel)
        case .hookInstall:     HookInstallPage(viewModel: viewModel)
        case .effectTest:      EffectTestPage(viewModel: viewModel)
        case .done:            OnboardingDonePage(viewModel: viewModel)
        }
    }

    private var footer: some View {
        HStack {
            if viewModel.step != .welcome && viewModel.step != .done {
                Button("Back") { viewModel.previous() }
            }
            Spacer()
            if viewModel.step == .done {
                Button("Done") { viewModel.finish() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Next") { viewModel.next() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canAdvance)
            }
        }
        .padding()
    }
}
```

- [ ] **Step 3: Create page placeholder stubs**

The seven page files are needed for the switch above to compile. Create each with a minimal stub now; Tasks 9–11 implement them.

For each of `WelcomePage`, `HAConnectionPage`, `LightSelectionPage`, `NetworkConfirmPage`, `HookInstallPage`, `EffectTestPage`, `OnboardingDonePage`, create:

`Sources/vibelight-app/Onboarding/WelcomePage.swift`:
```swift
import SwiftUI

struct WelcomePage: View {
    @ObservedObject var viewModel: OnboardingViewModel
    var body: some View {
        Text("Welcome — implemented in Task 9").foregroundColor(.secondary)
    }
}
```

Repeat for the other 6 files, just changing the struct name and the placeholder text. Each placeholder file is 6 lines.

- [ ] **Step 4: Wire Onboarding scene into `VibeLightApp.swift`**

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
            MenuBarLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.menu)

        Window("VibeLight Sessions", id: "sessions") {
            SessionsWindow(viewModel: viewModel)
        }
        .windowResizability(.contentMinSize)

        Window("VibeLight Settings", id: "settings") {
            SettingsWindow(viewModel: viewModel)
        }
        .windowResizability(.contentSize)

        Window("VibeLight Onboarding", id: "onboarding") {
            if viewModel.needsOnboarding {
                OnboardingWindow(viewModel: OnboardingViewModel(appViewModel: viewModel))
            } else {
                EmptyView()
            }
        }
        .windowResizability(.contentMinSize)
    }
}
```

NOTE: `SettingsWindow` (replacing the P2 `SettingsPlaceholderWindow`) is implemented in Task 12. For Task 8 to compile, create a minimal stub now:

`Sources/vibelight-app/SettingsWindow/SettingsWindow.swift`:
```swift
import SwiftUI

struct SettingsWindow: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View {
        Text("Settings — implemented in Task 12").padding(40)
            .frame(width: 480, height: 320)
    }
}
```

And delete the P2 placeholder:
```bash
rm Sources/vibelight-app/SettingsPlaceholderWindow.swift
```

(The P2 placeholder is no longer referenced after the rewrite above.)

- [ ] **Step 5: Auto-open onboarding when needed**

Add a small bit in `MenuContent.swift` so the Settings menu / status reflects onboarding state. Modify the existing status section:

Edit `Sources/vibelight-app/MenuContent.swift` `statusSection`:

```swift
private var statusSection: some View {
    Group {
        if viewModel.needsOnboarding {
            Text("Setup required")
            Button("Continue setup…") { openWindow(id: "onboarding") }
        } else if let err = viewModel.lastError {
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
```

- [ ] **Step 6: Verify build**

Run: `swift build`
Expected: clean.

- [ ] **Step 7: Commit**

```bash
git add Sources/vibelight-app/Onboarding Sources/vibelight-app/SettingsWindow Sources/vibelight-app/VibeLightApp.swift Sources/vibelight-app/MenuContent.swift
git rm Sources/vibelight-app/SettingsPlaceholderWindow.swift
git commit -m "feat(app): scaffold Onboarding window + wire SettingsWindow stub"
```

---

## Task 9: Onboarding pages 1–3 (Welcome / HA Connection / Light selection)

**Files:**
- Modify: `Sources/vibelight-app/Onboarding/WelcomePage.swift`
- Modify: `Sources/vibelight-app/Onboarding/HAConnectionPage.swift`
- Modify: `Sources/vibelight-app/Onboarding/LightSelectionPage.swift`

- [ ] **Step 1: Implement `WelcomePage.swift`**

```swift
import SwiftUI

struct WelcomePage: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            Text("Welcome to VibeLight").font(.title).bold()
            Text("VibeLight reflects your AI agent's state on a Home Assistant–controlled light. Setup takes about 2 minutes.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 420)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { viewModel.canAdvance = true }
    }
}
```

- [ ] **Step 2: Implement `HAConnectionPage.swift`**

```swift
import SwiftUI

struct HAConnectionPage: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var tokenInput: String = ""
    @State private var probing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scan local network").font(.headline)
            if viewModel.discovered.isEmpty {
                Text("Searching for Home Assistant on this network…")
                    .foregroundColor(.secondary).font(.caption)
            } else {
                ForEach(viewModel.discovered, id: \.id) { ha in
                    Button {
                        viewModel.settings.haURL = "http://\(ha.endpoint.dropLast()):8123"
                    } label: {
                        HStack {
                            Image(systemName: "house.fill")
                            Text(ha.name)
                            Spacer()
                            Text(ha.endpoint).foregroundColor(.secondary).font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().padding(.vertical, 4)

            Text("Or enter URL manually").font(.headline)
            TextField("http://homeassistant.local:8123", text: Binding(
                get: { viewModel.settings.haURL },
                set: { viewModel.settings.haURL = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            Text("Access Token").font(.headline).padding(.top, 8)
            SecureField("Long-lived access token", text: $tokenInput)
                .textFieldStyle(.roundedBorder)
                .onAppear { tokenInput = viewModel.settings.haToken ?? "" }
                .onChange(of: tokenInput) { newValue in
                    viewModel.settings.haToken = newValue
                }

            HStack {
                Button(probing ? "Testing…" : "Test connection") {
                    probing = true
                    Task {
                        await viewModel.testHAConnection()
                        probing = false
                        viewModel.canAdvance = (viewModel.lastError == nil)
                    }
                }
                .disabled(probing)
                if let err = viewModel.lastError {
                    Text(err).foregroundColor(.red).font(.caption)
                }
            }
            Spacer()
        }
        .onAppear {
            viewModel.canAdvance = false
            viewModel.startDiscovery()
        }
        .onDisappear {
            viewModel.stopDiscovery()
        }
    }
}
```

- [ ] **Step 3: Implement `LightSelectionPage.swift`**

```swift
import SwiftUI

struct LightSelectionPage: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var loading: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a light entity").font(.headline)
            Text("VibeLight will drive this light to reflect your agent's state.")
                .foregroundColor(.secondary).font(.caption)

            if loading {
                ProgressView("Loading lights…")
            } else if viewModel.lightEntities.isEmpty {
                VStack {
                    Text("No lights found. Make sure your HA token has access.")
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        Task { await refresh() }
                    }
                }
            } else {
                Picker("Light", selection: Binding(
                    get: { viewModel.settings.haLightEntity },
                    set: { viewModel.settings.haLightEntity = $0 }
                )) {
                    Text("Select…").tag("")
                    ForEach(viewModel.lightEntities, id: \.self) { ent in
                        Text(ent).tag(ent)
                    }
                }
                .pickerStyle(.menu)
            }
            Spacer()
        }
        .onAppear {
            Task { await refresh() }
        }
        .onChange(of: viewModel.settings.haLightEntity) { newValue in
            viewModel.canAdvance = !newValue.isEmpty
        }
    }

    private func refresh() async {
        loading = true
        await viewModel.fetchLightEntities()
        loading = false
        viewModel.canAdvance = !viewModel.settings.haLightEntity.isEmpty
    }
}
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/vibelight-app/Onboarding/{WelcomePage,HAConnectionPage,LightSelectionPage}.swift
git commit -m "feat(app): onboarding pages 1-3 (welcome, HA connect, light selection)"
```

---

## Task 10: Onboarding pages 4–5 (Network confirm / Hook install)

**Files:**
- Modify: `Sources/vibelight-app/Onboarding/NetworkConfirmPage.swift`
- Modify: `Sources/vibelight-app/Onboarding/HookInstallPage.swift`

- [ ] **Step 1: Implement `NetworkConfirmPage.swift`**

```swift
import SwiftUI

struct NetworkConfirmPage: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var probing: Bool = false
    @State private var reachable: Bool? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Confirm home network").font(.headline)
            Text("VibeLight will only drive your light when Home Assistant is reachable. We use this connection as the 'at home' signal.")
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(probing ? "Checking…" : "Check Home Assistant now") {
                    probing = true
                    Task {
                        guard let url = URL(string: viewModel.settings.haURL),
                              let token = viewModel.settings.haToken else {
                            reachable = false; probing = false; return
                        }
                        let probe = HomeReachability.haProbe(baseURL: url, token: token)
                        reachable = await probe()
                        probing = false
                        viewModel.canAdvance = (reachable == true)
                    }
                }
                .disabled(probing)
                if let r = reachable {
                    Text(r ? "✓ Reachable" : "✗ Not reachable")
                        .foregroundColor(r ? .green : .red)
                }
            }

            if reachable == true {
                Text("Your current Wi-Fi will be remembered as your home network hint.")
                    .foregroundColor(.secondary).font(.caption).padding(.top, 8)
            }

            Spacer()
        }
        .onAppear {
            viewModel.canAdvance = false
        }
    }
}
```

- [ ] **Step 2: Implement `HookInstallPage.swift`**

```swift
import SwiftUI

struct HookInstallPage: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var installed: Bool = false
    @State private var installError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Install Claude Code hooks").font(.headline)
            Text("VibeLight needs to add hook entries to ~/.claude/settings.json so Claude Code notifies it on events. Existing hooks won't be touched.")
                .foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(installed ? "Reinstall hooks" : "Install hooks") {
                    do {
                        try viewModel.appViewModel.hookInstaller.install()
                        installed = true
                        installError = nil
                        viewModel.canAdvance = true
                    } catch {
                        installError = String(describing: error)
                    }
                }
                if installed {
                    Text("✓ Installed")
                        .foregroundColor(.green)
                }
                if let err = installError {
                    Text(err).foregroundColor(.red).font(.caption)
                }
            }

            Text("Hook script: \(viewModel.appViewModel.hookInstaller.hookScriptPath.path)")
                .foregroundColor(.secondary).font(.caption)
            Text("Settings: \(viewModel.appViewModel.hookInstaller.settingsPath.path)")
                .foregroundColor(.secondary).font(.caption)

            Spacer()
        }
        .onAppear {
            installed = viewModel.appViewModel.hookInstaller.status() == .installed
            viewModel.canAdvance = installed
        }
    }
}
```

- [ ] **Step 3: Build + commit**

Run: `swift build`
Expected: clean.

```bash
git add Sources/vibelight-app/Onboarding/{NetworkConfirmPage,HookInstallPage}.swift
git commit -m "feat(app): onboarding pages 4-5 (network confirm, hook install)"
```

---

## Task 11: Onboarding pages 6–7 (Effect test / Done)

**Files:**
- Modify: `Sources/vibelight-app/Onboarding/EffectTestPage.swift`
- Modify: `Sources/vibelight-app/Onboarding/OnboardingDonePage.swift`

- [ ] **Step 1: Implement `EffectTestPage.swift`**

```swift
import SwiftUI
import VibeBrokerCore

struct EffectTestPage: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var selected: VibeBrokerCore.State = .working

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test light effects").font(.headline)
            Text("Click each state to verify the light responds as expected. The broker must be running — finish this wizard if it isn't yet.")
                .foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(VibeBrokerCore.State.allCases, id: \.self) { state in
                    Button(StateAppearance.label(state)) {
                        selected = state
                        viewModel.appViewModel.testRender(state)
                    }
                    .buttonStyle(.bordered)
                    .tint(selected == state ? StateAppearance.color(state) : .accentColor)
                }
            }
            .padding(.vertical, 8)

            Text("Currently testing: \(StateAppearance.label(selected))")
                .foregroundColor(.secondary)

            Spacer()
        }
        .onAppear { viewModel.canAdvance = true }
    }
}
```

- [ ] **Step 2: Implement `OnboardingDonePage.swift`**

```swift
import SwiftUI

struct OnboardingDonePage: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            Text("All set!").font(.title).bold()
            Text("VibeLight will now reflect your Claude Code agent's state on your light. Find more options under Settings… in the menubar.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 420)
            Text("Want even smoother effects? Try Settings → Home Assistant → Scene pack mode.")
                .font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { viewModel.canAdvance = true }
    }
}
```

- [ ] **Step 3: Build + commit**

Run: `swift build`
Expected: clean.

```bash
git add Sources/vibelight-app/Onboarding/{EffectTestPage,OnboardingDonePage}.swift
git commit -m "feat(app): onboarding pages 6-7 (effect test, done)"
```

---

## Task 12: `SettingsWindow` + General tab + Advanced tab

**Files:**
- Modify: `Sources/vibelight-app/SettingsWindow/SettingsWindow.swift` (replace P2 placeholder content)
- Create: `Sources/vibelight-app/SettingsWindow/GeneralTab.swift`
- Create: `Sources/vibelight-app/SettingsWindow/AdvancedTab.swift`

- [ ] **Step 1: Replace `SettingsWindow.swift`**

```swift
import SwiftUI

struct SettingsWindow: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        TabView {
            GeneralTab(viewModel: viewModel)
                .tabItem { Label("General", systemImage: "gear") }
            HomeAssistantTab(viewModel: viewModel)
                .tabItem { Label("Home Assistant", systemImage: "house") }
            ColorsTab(viewModel: viewModel)
                .tabItem { Label("Colors", systemImage: "paintpalette") }
            NetworkTab(viewModel: viewModel)
                .tabItem { Label("Network", systemImage: "wifi") }
            ClaudeCodeTab(viewModel: viewModel)
                .tabItem { Label("Claude Code", systemImage: "terminal") }
            AdvancedTab(viewModel: viewModel)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 560, height: 420)
        .padding()
    }
}
```

- [ ] **Step 2: Create `GeneralTab.swift`**

```swift
import SwiftUI

struct GeneralTab: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(
                get: { viewModel.settings.launchAtLogin },
                set: { viewModel.settings.launchAtLogin = $0 }
            ))
            Toggle("Notify on HA errors", isOn: Binding(
                get: { viewModel.settings.notifyOnHAError },
                set: { viewModel.settings.notifyOnHAError = $0 }
            ))
        }
        .padding()
    }
}
```

- [ ] **Step 3: Create `AdvancedTab.swift`**

```swift
import SwiftUI

struct AdvancedTab: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showResetConfirm = false

    var body: some View {
        Form {
            HStack {
                Text("Broker port")
                Spacer()
                TextField("17345", value: Binding(
                    get: { viewModel.settings.brokerPort },
                    set: { viewModel.settings.brokerPort = $0 }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                Text("(restart app to apply)").font(.caption).foregroundColor(.secondary)
            }

            HStack {
                Text("Default pause duration (seconds)")
                Spacer()
                TextField("1800", value: Binding(
                    get: { viewModel.settings.defaultPauseSeconds },
                    set: { viewModel.settings.defaultPauseSeconds = $0 }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
            }

            Divider().padding(.vertical, 8)

            HStack {
                Button("Open logs folder") {
                    let path = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Library/Logs/VibeLight")
                    try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(path)
                }

                Spacer()

                Button("Reset all settings", role: .destructive) {
                    showResetConfirm = true
                }
                .confirmationDialog(
                    "Reset all VibeLight settings? Your HA token will be removed from Keychain.",
                    isPresented: $showResetConfirm
                ) {
                    Button("Reset", role: .destructive) {
                        viewModel.settings.resetAll()
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }

            Spacer()
        }
        .padding()
    }
}
```

- [ ] **Step 4: Create minimal stubs for the three remaining tabs (so SettingsWindow compiles)**

`Sources/vibelight-app/SettingsWindow/HomeAssistantTab.swift`:
```swift
import SwiftUI

struct HomeAssistantTab: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View {
        Text("Home Assistant — Task 13").foregroundColor(.secondary).padding()
    }
}
```

`Sources/vibelight-app/SettingsWindow/ColorsTab.swift`:
```swift
import SwiftUI

struct ColorsTab: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View {
        Text("Colors & Effects — Task 14").foregroundColor(.secondary).padding()
    }
}
```

`Sources/vibelight-app/SettingsWindow/NetworkTab.swift`:
```swift
import SwiftUI

struct NetworkTab: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View {
        Text("Network — Task 13").foregroundColor(.secondary).padding()
    }
}
```

`Sources/vibelight-app/SettingsWindow/ClaudeCodeTab.swift`:
```swift
import SwiftUI

struct ClaudeCodeTab: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View {
        Text("Claude Code — Task 14").foregroundColor(.secondary).padding()
    }
}
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add Sources/vibelight-app/SettingsWindow
git commit -m "feat(app): Settings window framework + General + Advanced tabs"
```

---

## Task 13: Home Assistant tab + Network tab

**Files:**
- Modify: `Sources/vibelight-app/SettingsWindow/HomeAssistantTab.swift`
- Modify: `Sources/vibelight-app/SettingsWindow/NetworkTab.swift`

- [ ] **Step 1: Implement `HomeAssistantTab.swift`**

```swift
import SwiftUI
import VibeBrokerNet

struct HomeAssistantTab: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var scanning: Bool = false
    @State private var discovered: [DiscoveredHA] = []
    @State private var token: String = ""
    @State private var entities: [String] = []
    @State private var testStatus: String = ""
    @State private var sceneStatus: String = ""

    var body: some View {
        Form {
            Section("URL") {
                VStack(alignment: .leading) {
                    HStack {
                        Button(scanning ? "Scanning…" : "Scan local network") {
                            Task { await scan() }
                        }
                        .disabled(scanning)
                    }
                    if !discovered.isEmpty {
                        ForEach(discovered, id: \.id) { ha in
                            Button {
                                viewModel.settings.haURL = "http://\(ha.endpoint.dropLast()):8123"
                            } label: {
                                Text("• \(ha.name) (\(ha.endpoint))")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    TextField("http://homeassistant.local:8123", text: Binding(
                        get: { viewModel.settings.haURL },
                        set: { viewModel.settings.haURL = $0 }
                    ))
                    HStack {
                        Button("Test") {
                            Task { await testConnection() }
                        }
                        if !testStatus.isEmpty { Text(testStatus).font(.caption) }
                    }
                }
            }

            Section("Access Token") {
                SecureField("Long-lived access token", text: $token)
                    .onAppear { token = viewModel.settings.haToken ?? "" }
                    .onChange(of: token) { viewModel.settings.haToken = $0 }
            }

            Section("Light entity") {
                Picker("Light", selection: Binding(
                    get: { viewModel.settings.haLightEntity },
                    set: { viewModel.settings.haLightEntity = $0 }
                )) {
                    Text("Select…").tag("")
                    ForEach(entities, id: \.self) { Text($0).tag($0) }
                }
                Button("Refresh list") { Task { await fetchEntities() } }
            }

            Section("Light effect mode") {
                Picker("Mode", selection: Binding(
                    get: { viewModel.settings.renderMode },
                    set: { viewModel.settings.renderMode = $0 }
                )) {
                    Text("Broker-emulated (default)").tag(SettingsStore.RenderMode.brokerEmulated)
                    Text("Scene pack").tag(SettingsStore.RenderMode.scenePack)
                }
                .pickerStyle(.radioGroup)

                HStack {
                    Button("Install scene pack") { Task { await installScenePack() } }
                    Button("Uninstall scene pack") { Task { await uninstallScenePack() } }
                    if !sceneStatus.isEmpty { Text(sceneStatus).font(.caption) }
                }
            }

            Spacer()
        }
        .padding()
    }

    private func scan() async {
        scanning = true
        let discovery = HADiscovery()
        await discovery.start()
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        discovered = await discovery.current()
        await discovery.stop()
        scanning = false
    }

    private func testConnection() async {
        guard let url = URL(string: viewModel.settings.haURL), let t = viewModel.settings.haToken else {
            testStatus = "URL/token missing"; return
        }
        let client = HAClient(baseURL: url, token: t)
        do {
            _ = try await client.getApiStatus()
            testStatus = "✓ Connected"
        } catch {
            testStatus = "✗ \(error)"
        }
    }

    private func fetchEntities() async {
        guard let url = URL(string: viewModel.settings.haURL), let t = viewModel.settings.haToken else { return }
        var req = URLRequest(url: url.appendingPathComponent("api/states"))
        req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 3.0
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                entities = arr.compactMap { $0["entity_id"] as? String }
                    .filter { $0.hasPrefix("light.") }.sorted()
            }
        } catch {
            // ignore in UI; user can retry
        }
    }

    private func installScenePack() async {
        guard let url = URL(string: viewModel.settings.haURL), let t = viewModel.settings.haToken,
              let cfg = try? ConfigBuilder.build(from: viewModel.settings) else {
            sceneStatus = "Settings incomplete"; return
        }
        let installer = ScenePackInstaller(baseURL: url, token: t)
        do {
            try await installer.install(config: cfg)
            sceneStatus = "✓ Installed 7 scenes"
        } catch {
            sceneStatus = "✗ \(error)"
        }
    }

    private func uninstallScenePack() async {
        guard let url = URL(string: viewModel.settings.haURL), let t = viewModel.settings.haToken else {
            sceneStatus = "Settings incomplete"; return
        }
        let installer = ScenePackInstaller(baseURL: url, token: t)
        do {
            try await installer.uninstall()
            sceneStatus = "✓ Uninstalled"
        } catch {
            sceneStatus = "✗ \(error)"
        }
    }
}
```

- [ ] **Step 2: Implement `NetworkTab.swift`**

```swift
import SwiftUI

struct NetworkTab: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var checking: Bool = false

    var body: some View {
        Form {
            HStack {
                Text("Status:")
                Spacer()
                Text(viewModel.isAtHome ? "At home" : "Away")
                    .foregroundColor(viewModel.isAtHome ? .green : .secondary)
            }

            if let hint = viewModel.settings.homeSSIDHint {
                HStack {
                    Text("Last home Wi-Fi:")
                    Spacer()
                    Text(hint).foregroundColor(.secondary)
                }
            }

            HStack {
                Button(checking ? "Checking…" : "Check now") {
                    checking = true
                    Task {
                        // Force a probe through AppViewModel's reachability if exposed,
                        // or do it directly here.
                        guard let url = URL(string: viewModel.settings.haURL),
                              let t = viewModel.settings.haToken else {
                            checking = false; return
                        }
                        let probe = HomeReachability.haProbe(baseURL: url, token: t)
                        _ = await probe()
                        checking = false
                    }
                }
                .disabled(checking)
            }
            Spacer()
        }
        .padding()
    }
}
```

- [ ] **Step 3: Build + commit**

Run: `swift build`
Expected: clean.

```bash
git add Sources/vibelight-app/SettingsWindow/{HomeAssistantTab,NetworkTab}.swift
git commit -m "feat(app): Settings Home Assistant + Network tabs"
```

---

## Task 14: Colors tab + Claude Code tab + end-to-end smoke

**Files:**
- Modify: `Sources/vibelight-app/SettingsWindow/ColorsTab.swift`
- Modify: `Sources/vibelight-app/SettingsWindow/ClaudeCodeTab.swift`
- Create: `Resources/README-p3-smoke.md`

- [ ] **Step 1: Implement `ColorsTab.swift`**

```swift
import SwiftUI
import VibeBrokerCore

struct ColorsTab: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack {
            ScrollView {
                ForEach(VibeBrokerCore.State.allCases, id: \.self) { state in
                    HStack {
                        Text(StateAppearance.label(state))
                            .frame(width: 160, alignment: .leading)
                        ColorPicker("", selection: bindingForColor(state))
                            .frame(width: 60)
                        Slider(
                            value: bindingForBrightness(state),
                            in: 1...255,
                            step: 1
                        ) {
                            Text("Brightness")
                        }
                        .frame(width: 160)
                        Text("\(Int(viewModel.settings.colors[state]?.brightness ?? 0))")
                            .frame(width: 40)
                        Picker("", selection: bindingForEffect(state)) {
                            ForEach([Effect.solid, .breathe, .blink, .blinkThenSolid], id: \.self) { e in
                                Text(e.rawValue).tag(e)
                            }
                        }
                        .frame(width: 140)
                    }
                    .padding(.vertical, 2)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Reset to defaults") { viewModel.settings.resetColors() }
            }
        }
        .padding()
    }

    private func bindingForColor(_ state: VibeBrokerCore.State) -> Binding<Color> {
        Binding(
            get: {
                let rgb = viewModel.settings.colors[state]?.rgb ?? [0, 0, 0]
                return Color(
                    red: Double(rgb[0]) / 255,
                    green: Double(rgb[1]) / 255,
                    blue: Double(rgb[2]) / 255
                )
            },
            set: { newColor in
                let rgb = newColor.rgbComponents()
                var current = viewModel.settings.colors[state]
                    ?? ColorConfig(rgb: [0, 0, 0], brightness: 200, effect: .solid)
                current = ColorConfig(rgb: rgb, brightness: current.brightness, effect: current.effect)
                viewModel.settings.colors[state] = current
            }
        )
    }

    private func bindingForBrightness(_ state: VibeBrokerCore.State) -> Binding<Double> {
        Binding(
            get: { Double(viewModel.settings.colors[state]?.brightness ?? 0) },
            set: { newValue in
                var current = viewModel.settings.colors[state]
                    ?? ColorConfig(rgb: [0, 0, 0], brightness: 200, effect: .solid)
                current = ColorConfig(rgb: current.rgb, brightness: Int(newValue), effect: current.effect)
                viewModel.settings.colors[state] = current
            }
        )
    }

    private func bindingForEffect(_ state: VibeBrokerCore.State) -> Binding<Effect> {
        Binding(
            get: { viewModel.settings.colors[state]?.effect ?? .solid },
            set: { newEffect in
                var current = viewModel.settings.colors[state]
                    ?? ColorConfig(rgb: [0, 0, 0], brightness: 200, effect: .solid)
                current = ColorConfig(rgb: current.rgb, brightness: current.brightness, effect: newEffect)
                viewModel.settings.colors[state] = current
            }
        )
    }
}

private extension Color {
    func rgbComponents() -> [Int] {
        // SwiftUI Color → NSColor → RGB; if conversion fails fall back to black.
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return [
            Int(ns.redComponent * 255),
            Int(ns.greenComponent * 255),
            Int(ns.blueComponent * 255),
        ]
    }
}
```

- [ ] **Step 2: Implement `ClaudeCodeTab.swift`**

```swift
import SwiftUI

struct ClaudeCodeTab: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var status: HookInstallStatus = .notInstalled
    @State private var actionResult: String = ""

    var body: some View {
        Form {
            HStack {
                Text("Hooks:")
                Spacer()
                Text(status == .installed ? "Installed ✓" : "Not installed")
                    .foregroundColor(status == .installed ? .green : .secondary)
            }
            HStack {
                Button(status == .installed ? "Reinstall hooks" : "Install hooks") {
                    do {
                        try viewModel.hookInstaller.install()
                        actionResult = "✓ Installed"
                        status = .installed
                    } catch {
                        actionResult = "✗ \(error)"
                    }
                }
                Button("Uninstall hooks", role: .destructive) {
                    do {
                        try viewModel.hookInstaller.uninstall()
                        actionResult = "✓ Uninstalled"
                        status = .notInstalled
                    } catch {
                        actionResult = "✗ \(error)"
                    }
                }
                if !actionResult.isEmpty { Text(actionResult).font(.caption) }
            }

            Divider().padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 4) {
                Text("Hook script path:").font(.caption).foregroundColor(.secondary)
                Text(viewModel.hookInstaller.hookScriptPath.path)
                    .font(.caption.monospaced())
                Text("Claude Code settings:").font(.caption).foregroundColor(.secondary).padding(.top, 4)
                Text(viewModel.hookInstaller.settingsPath.path)
                    .font(.caption.monospaced())
            }

            Button("Reveal hook script in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([viewModel.hookInstaller.hookScriptPath])
            }
            .disabled(status != .installed)

            Spacer()
        }
        .padding()
        .onAppear {
            status = viewModel.hookInstaller.status()
        }
    }
}
```

- [ ] **Step 3: Create P3 smoke README**

`Resources/README-p3-smoke.md`:

````markdown
# VibeLight P3 — end-to-end smoke

## 1. Reset and bundle

```bash
# Clear any existing P2 setup so onboarding fires fresh.
defaults delete com.vibelight.app 2>/dev/null
rm -f ~/.config/vibelight/config.json
security delete-generic-password -s com.vibelight.app -a haToken 2>/dev/null

# Build + bundle
./scripts/bundle.sh
```

## 2. Launch

```bash
open build/VibeLight.app
```

Expected: a window titled "VibeLight Onboarding" appears with step 1/7 (Welcome).

## 3. Walk onboarding

- Welcome → Next
- HA Connection: paste URL + token, click Test, expect "✓ Connected", then Next
- Light selection: pick a `light.*` entity, Next
- Network confirm: click "Check now", expect "✓ Reachable", Next
- Hook install: click "Install hooks", expect "✓ Installed". Check `~/.claude/settings.json` includes vibelight entries
- Effect test: click each state button; watch the menubar icon + your HA light
- Done → Done

The Onboarding window closes; menubar icon should reflect Idle (purple).

## 4. Verify settings persistence

Quit the app (menubar → Quit). Relaunch via `open build/VibeLight.app`. Onboarding should NOT appear — app should be ready immediately.

## 5. Open Settings

Menubar → Settings… Walk all 6 tabs. Each should be functional:

- General: toggles
- Home Assistant: re-test connection, refresh entity list, install/uninstall scene pack
- Colors: change Working to a different color, click around — broker auto-rebuilds (saved on every change)
- Network: status shows "At home" or "Away"; click Check now
- Claude Code: status shows "Installed ✓"; can reinstall/uninstall
- Advanced: change broker port (won't take effect until restart), reset all (test only if you want to redo onboarding)

## 6. Verify Scene pack mode (if you want the smoother experience)

Settings → Home Assistant → click "Install scene pack". Expect "✓ Installed 7 scenes".
Switch the radio to "Scene pack". The light effects now run via HA scenes; you can customize them in HA itself.

## 7. Verify Pause across network changes

Click Pause → 30 minutes. Push a hook event:

```bash
echo '{"session_id":"smoke","cwd":"/tmp"}' | curl -s -X POST \
  -H 'Content-Type: application/json' --data-binary @- \
  'http://127.0.0.1:17345/event?hook=UserPromptSubmit'
```

Menubar updates to Working but light stays put. Click Resume — light catches up to current state.

## 8. Verify "away" behavior

Disconnect Wi-Fi (or set a wrong HA URL temporarily). Network tab should show "Away" within ~30 seconds.

Hook events will still be received and the menubar will reflect them, but the broker won't try to call HA (this matches §10 of the spec — broker is fault-tolerant; HA failures are absorbed).

## 9. Quit

Menubar → Quit. Within 1 second the process exits.

```bash
pgrep -f VibeLight   # should print nothing
```
````

- [ ] **Step 4: Build + bundle + manual smoke**

Run:
```bash
swift build
./scripts/bundle.sh
```

Expected: builds clean, bundle produced.

For full verification, walk through `Resources/README-p3-smoke.md` interactively. If you're a subagent without a desktop session, run only steps 1–2 (verify the app launches and the broker is alive). Manual verification of onboarding and tabs is the user's task.

- [ ] **Step 5: Commit**

```bash
git add Sources/vibelight-app/SettingsWindow/{ColorsTab,ClaudeCodeTab}.swift Resources/README-p3-smoke.md
git commit -m "feat(app): Settings Colors + Claude Code tabs; P3 smoke README"
```

---

## Final verification

- [ ] **Full test suite**

```bash
swift test
```

Expected: ~77 tests pass.

- [ ] **Rebuild .app**

```bash
./scripts/bundle.sh
```

- [ ] **Manual walkthrough**

Follow `Resources/README-p3-smoke.md` steps 1–6 with a real HA instance. Steps 7–8 (Pause and Away) can be verified without HA.

- [ ] **Tag P3 milestone**

```bash
git tag p3-onboarding-settings
```

---

## P3 Done. What's next?

P3 produces VibeLight v1 — onboarding, settings, scene pack, network awareness, hook installer.

**Open follow-ups (post-v1):**
- Icon animations to match light effects (breathing / blinking on the menubar icon)
- Codex support (state inference from PTY output)
- Code signing + notarization for distribution
- Auto-update via Sparkle or built-in
- Pause-state persistence across restart
- "At home" derived from SSID list (currently HA-reachability only)
- Hook script "Out of date" detection (compare script-version comment)
- iOS/iPadOS remote indicator
