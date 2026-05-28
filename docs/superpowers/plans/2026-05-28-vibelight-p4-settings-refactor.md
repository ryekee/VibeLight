# VibeLight P4: Settings Refactor + Cold-Start Discovery + Login Item — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Settings window with a macOS Ventura–style sidebar layout (sections + grouped rows with titles, descriptions, and inline controls), wire `Launch at login` to real `SMAppService` registration, and add cold-start transcript discovery so sessions started before VibeLight launches are recovered automatically.

**Architecture:** Settings becomes a `NavigationSplitView` with a sidebar of 7 destinations in 3 sections (main / Advanced / VibeLight). Reusable `SettingsSection` + `SettingsRow` primitives normalize the visual style (title, description, control). Login at login uses Apple's `SMAppService.mainApp.register/unregister`. Cold-start runs a new `TranscriptDiscovery` actor in `VibeBrokerNet` that scans `~/.claude/projects/*/*.jsonl`, extracts session ids by filename, and seeds the broker's `SessionStore` with idle entries — actual state updates flow from the hook stream as normal.

**Tech Stack:** Swift 5.9+, SwiftUI (`NavigationSplitView`), `ServiceManagement.SMAppService`, Foundation `FileManager`, macOS 13+. Zero new third-party dependencies.

**Scope (P4 only):**
- New sidebar Settings layout (7 destinations: General, Integrations, Light Effects, Network, Scene Pack, Diagnostics, About)
- Reusable `SettingsSection` and `SettingsRow` views
- Reorganize existing Settings content into the new pages (Integrations folds HA + Claude Code hook status; Scene Pack extracted to its own page; Colors becomes Light Effects with 3 grouped subsections)
- New About page with version, source link, license
- `Launch at login` actually registers a Login Item via `SMAppService.mainApp` (`SMAppService` requires the app to be in `/Applications` or signed; for our unsigned dev bundle, log + no-op on failure)
- `TranscriptDiscovery` actor: scan `~/.claude/projects/*/*.jsonl`, extract session ids, seed SessionStore (cap: 40 files within 24h, mirrors open-vibe-island's approach)
- `BrokerHost.discoverHistoricalSessions()` entry point invoked from AppViewModel.bootstrap
- P4 smoke README

**Out of scope (deferred to P5):**
- Codex hook installer (`~/.codex/config.toml` + `[features].hooks = true`)
- Codex Desktop App JSON-RPC subprocess client
- Reading transcript file bodies to reconstruct in-flight state (we only seed sessions as idle in P4)
- Terminal-pane jump-to-source (env-var capture in hook script)
- Icon animations on the menubar
- Code signing / notarization
- Two-poll liveness debounce (still 5-minute TTL)

**Why this split:** Settings is a UI overhaul that benefits from a single focused pass (sidebar primitives + every page rewritten in the new idiom). Cold-start is a small but standalone backend feature that pairs cleanly with bootstrap changes. Codex deserves its own plan because it has two distinct integration paths (CLI hooks vs Desktop app-server).

---

## File Structure

```
VibeLight/
├── Sources/
│   ├── VibeBrokerCore/                       # unchanged
│   ├── VibeBrokerNet/
│   │   ├── TranscriptDiscovery.swift         # NEW
│   │   ├── BrokerHost.swift                  # MODIFY: add discoverHistoricalSessions
│   │   └── ... (others unchanged)
│   └── vibelight-app/
│       ├── Settings/
│       │   ├── LoginItemManager.swift        # NEW: SMAppService wrapper
│       │   ├── SettingsStore.swift           # MODIFY: launchAtLogin didSet → LoginItemManager
│       │   └── ... (others unchanged)
│       ├── SettingsWindow/
│       │   ├── SettingsWindow.swift          # MODIFY: NavigationSplitView shell
│       │   ├── SettingsDestination.swift     # NEW: enum of pages
│       │   ├── SettingsSection.swift         # NEW: reusable section/row primitives
│       │   ├── GeneralPage.swift             # NEW (replaces GeneralTab)
│       │   ├── IntegrationsPage.swift        # NEW (replaces HomeAssistantTab; folds ClaudeCodeTab)
│       │   ├── LightEffectsPage.swift        # NEW (replaces ColorsTab with 3 grouped sections)
│       │   ├── NetworkPage.swift             # NEW (replaces NetworkTab)
│       │   ├── ScenePackPage.swift           # NEW (extracted from HomeAssistantTab)
│       │   ├── DiagnosticsPage.swift         # NEW (replaces AdvancedTab)
│       │   ├── AboutPage.swift               # NEW
│       │   ├── GeneralTab.swift              # DELETE
│       │   ├── HomeAssistantTab.swift        # DELETE
│       │   ├── ColorsTab.swift               # DELETE
│       │   ├── NetworkTab.swift              # DELETE
│       │   ├── ClaudeCodeTab.swift           # DELETE
│       │   └── AdvancedTab.swift             # DELETE
│       ├── AppViewModel.swift                # MODIFY: bootstrap → invoke discovery
│       └── ... (others unchanged)
└── Tests/
    └── VibeBrokerNetTests/
        └── TranscriptDiscoveryTests.swift    # NEW
```

---

## Task Index

| # | Task | Test layer |
|---|---|---|
| 1 | `SettingsDestination` enum + `SettingsSection` / `SettingsRow` primitives | build only |
| 2 | `SettingsWindow` NavigationSplitView shell + nav state | manual smoke |
| 3 | `GeneralPage` + `LoginItemManager` (SMAppService) | manual smoke |
| 4 | `IntegrationsPage` (HA + hook status folded together) | manual smoke |
| 5 | `LightEffectsPage` (3 grouped subsections) | manual smoke |
| 6 | `NetworkPage` | manual smoke |
| 7 | `ScenePackPage` (extracted) | manual smoke |
| 8 | `DiagnosticsPage` + `AboutPage` + delete old `*Tab` files | manual smoke |
| 9 | `TranscriptDiscovery` actor | unit |
| 10 | `BrokerHost.discoverHistoricalSessions` + AppViewModel hookup | unit + manual |
| 11 | P4 smoke README + final .app build | manual |

---

## Task 1: `SettingsDestination` + reusable section/row primitives

**Files:**
- Create: `Sources/vibelight-app/SettingsWindow/SettingsDestination.swift`
- Create: `Sources/vibelight-app/SettingsWindow/SettingsSection.swift`

`SettingsDestination` enumerates the 7 pages + their sidebar metadata (label, system image, tint color). The section/row primitives normalize spacing and visual style across all pages — they correspond to the grouped boxes in the reference screenshot.

- [ ] **Step 1: Create `SettingsDestination.swift`**

`Sources/vibelight-app/SettingsWindow/SettingsDestination.swift`:

```swift
import SwiftUI

enum SettingsDestination: String, CaseIterable, Identifiable, Hashable {
    case general
    case integrations
    case lightEffects
    case network
    case scenePack
    case diagnostics
    case about

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general:      return "General"
        case .integrations: return "Integrations"
        case .lightEffects: return "Light Effects"
        case .network:      return "Network"
        case .scenePack:    return "Scene Pack"
        case .diagnostics:  return "Diagnostics"
        case .about:        return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general:      return "gear"
        case .integrations: return "rectangle.connected.to.line.below"
        case .lightEffects: return "lightbulb.fill"
        case .network:      return "wifi"
        case .scenePack:    return "rectangle.stack.fill"
        case .diagnostics:  return "wrench.and.screwdriver.fill"
        case .about:        return "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general:      return .gray
        case .integrations: return .blue
        case .lightEffects: return .yellow
        case .network:      return .green
        case .scenePack:    return .purple
        case .diagnostics:  return .orange
        case .about:        return .blue
        }
    }

    /// Sidebar grouping. `nil` puts the item in the unlabeled top group.
    var group: String? {
        switch self {
        case .general, .integrations, .lightEffects, .network: return nil
        case .scenePack, .diagnostics:                          return "Advanced"
        case .about:                                            return "VibeLight"
        }
    }
}
```

- [ ] **Step 2: Create `SettingsSection.swift`**

`Sources/vibelight-app/SettingsWindow/SettingsSection.swift`:

```swift
import SwiftUI

/// Page-scope header above a grouped box (e.g. "Session", "Interactions").
struct SettingsSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

/// One row inside a grouped box: title (+ optional description) on the left,
/// control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    let description: String?
    @ViewBuilder var control: () -> Control

    init(_ title: String, description: String? = nil,
         @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.description = description
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            control()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}

/// Container that wraps a set of rows in a rounded grouped box.
struct SettingsBox<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A header centered above the page content (icon + page title).
struct SettingsPageHeader: View {
    let destination: SettingsDestination
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: destination.systemImage)
                .frame(width: 22, height: 22)
                .foregroundColor(.white)
                .background(destination.tint)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Text(destination.label).font(.title2).bold()
        }
        .padding(.bottom, 8)
    }
}
```

- [ ] **Step 3: Verify build**

Run: `swift build`
Expected: clean. (No tests added; these are pure view scaffolding.)

- [ ] **Step 4: Commit**

```bash
git add Sources/vibelight-app/SettingsWindow/SettingsDestination.swift Sources/vibelight-app/SettingsWindow/SettingsSection.swift
git commit -m "feat(app): add Settings destination enum and reusable section/row primitives"
```

---

## Task 2: `SettingsWindow` NavigationSplitView shell

**Files:**
- Modify: `Sources/vibelight-app/SettingsWindow/SettingsWindow.swift`

Replace the existing TabView with a `NavigationSplitView`. Sidebar binds to a `@State` `selection: SettingsDestination?`. Detail area is a switch on selection rendering placeholder text for now — Tasks 3–8 fill in the real pages, but the shell must compile and navigate today.

- [ ] **Step 1: Replace `SettingsWindow.swift`**

`Sources/vibelight-app/SettingsWindow/SettingsWindow.swift`:

```swift
import SwiftUI

struct SettingsWindow: View {
    @ObservedObject var viewModel: AppViewModel
    @SwiftUI.State private var selection: SettingsDestination? = .general

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, minHeight: 480)
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ForEach(SettingsDestination.allCases.filter { $0.group == nil }) { dest in
                    sidebarRow(dest)
                }
            }
            Section("Advanced") {
                ForEach(SettingsDestination.allCases.filter { $0.group == "Advanced" }) { dest in
                    sidebarRow(dest)
                }
            }
            Section("VibeLight") {
                ForEach(SettingsDestination.allCases.filter { $0.group == "VibeLight" }) { dest in
                    sidebarRow(dest)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }

    private func sidebarRow(_ destination: SettingsDestination) -> some View {
        Label {
            Text(destination.label)
        } icon: {
            Image(systemName: destination.systemImage)
                .frame(width: 20, height: 20)
                .foregroundColor(.white)
                .background(destination.tint)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .tag(destination)
    }

    @ViewBuilder
    private var detail: some View {
        let dest = selection ?? .general
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsPageHeader(destination: dest)
                pageContent(for: dest)
                Spacer(minLength: 24)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func pageContent(for destination: SettingsDestination) -> some View {
        switch destination {
        case .general:      GeneralPage(viewModel: viewModel)
        case .integrations: IntegrationsPage(viewModel: viewModel)
        case .lightEffects: LightEffectsPage(viewModel: viewModel)
        case .network:      NetworkPage(viewModel: viewModel)
        case .scenePack:    ScenePackPage(viewModel: viewModel)
        case .diagnostics:  DiagnosticsPage(viewModel: viewModel)
        case .about:        AboutPage()
        }
    }
}
```

- [ ] **Step 2: Add temporary stubs for each new page**

To keep the build green while we work, add ALL 7 page files as one-line stubs now. Tasks 3–8 will fill them in. Create each file with `View` returning `Text("<Page Name> — implemented in P4 Task X")`.

Create the following 7 files. Each has the same structure — only the struct name and placeholder text differ:

`Sources/vibelight-app/SettingsWindow/GeneralPage.swift`:
```swift
import SwiftUI

struct GeneralPage: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View {
        Text("General — Task 3").foregroundColor(.secondary)
    }
}
```

`Sources/vibelight-app/SettingsWindow/IntegrationsPage.swift`:
```swift
import SwiftUI

struct IntegrationsPage: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View {
        Text("Integrations — Task 4").foregroundColor(.secondary)
    }
}
```

`Sources/vibelight-app/SettingsWindow/LightEffectsPage.swift`:
```swift
import SwiftUI

struct LightEffectsPage: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View {
        Text("Light Effects — Task 5").foregroundColor(.secondary)
    }
}
```

`Sources/vibelight-app/SettingsWindow/NetworkPage.swift`:
```swift
import SwiftUI

struct NetworkPage: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View {
        Text("Network — Task 6").foregroundColor(.secondary)
    }
}
```

`Sources/vibelight-app/SettingsWindow/ScenePackPage.swift`:
```swift
import SwiftUI

struct ScenePackPage: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View {
        Text("Scene Pack — Task 7").foregroundColor(.secondary)
    }
}
```

`Sources/vibelight-app/SettingsWindow/DiagnosticsPage.swift`:
```swift
import SwiftUI

struct DiagnosticsPage: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View {
        Text("Diagnostics — Task 8").foregroundColor(.secondary)
    }
}
```

`Sources/vibelight-app/SettingsWindow/AboutPage.swift`:
```swift
import SwiftUI

struct AboutPage: View {
    var body: some View {
        Text("About — Task 8").foregroundColor(.secondary)
    }
}
```

- [ ] **Step 3: Verify build**

Run: `swift build`
Expected: clean. Note that the old `GeneralTab.swift`, `HomeAssistantTab.swift`, `ColorsTab.swift`, `NetworkTab.swift`, `ClaudeCodeTab.swift`, `AdvancedTab.swift` still exist — they're not referenced anymore (SettingsWindow uses the new `*Page` types). Old files will be deleted in Task 8.

If you get "ambiguous reference" or "duplicate symbol" errors because old tab files clash with new page files, ignore them — they're independent types. If something does collide, delete the unused old file immediately.

- [ ] **Step 4: Smoke**

```bash
swift run vibelight-app &
APP_PID=$!
sleep 3
```

Open Settings via the menubar. You should see a sidebar with the 7 destinations in 3 sections; clicking each shows the placeholder text. Quit:

```bash
kill -INT $APP_PID 2>/dev/null || true
wait $APP_PID 2>/dev/null || true
```

- [ ] **Step 5: Commit**

```bash
git add Sources/vibelight-app/SettingsWindow
git commit -m "feat(app): replace TabView Settings with NavigationSplitView sidebar shell"
```

---

## Task 3: `GeneralPage` + `LoginItemManager`

**Files:**
- Create: `Sources/vibelight-app/Settings/LoginItemManager.swift`
- Modify: `Sources/vibelight-app/Settings/SettingsStore.swift`
- Modify (replace stub): `Sources/vibelight-app/SettingsWindow/GeneralPage.swift`

`LoginItemManager` wraps `SMAppService.mainApp` register/unregister. `SettingsStore.launchAtLogin.didSet` now syncs the SMAppService state. `GeneralPage` shows two toggles plus a status indicator if SMAppService registration fails (e.g., unsigned dev bundle).

- [ ] **Step 1: Create `LoginItemManager.swift`**

`Sources/vibelight-app/Settings/LoginItemManager.swift`:

```swift
import Foundation
import ServiceManagement

enum LoginItemManager {
    enum SyncResult {
        case ok
        case notSupported    // SMAppService unavailable (e.g. unsigned bundle outside /Applications)
        case failed(String)
    }

    @discardableResult
    static func sync(enabled: Bool) -> SyncResult {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status == .enabled { return .ok }
                try service.register()
            } else {
                if service.status == .notRegistered { return .ok }
                try service.unregister()
            }
            return .ok
        } catch let err as NSError {
            // For unsigned dev bundles SMAppService returns error code 1.
            if err.domain == "SMAppServiceErrorDomain" && err.code == 1 {
                return .notSupported
            }
            return .failed(err.localizedDescription)
        }
    }

    static var currentStatus: SMAppService.Status {
        SMAppService.mainApp.status
    }
}
```

- [ ] **Step 2: Wire `SettingsStore.launchAtLogin` to LoginItemManager**

In `Sources/vibelight-app/Settings/SettingsStore.swift`, replace the existing `launchAtLogin` declaration:

```swift
@Published var launchAtLogin: Bool {
    didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin.rawValue); fire() }
}
```

with:

```swift
@Published var launchAtLogin: Bool {
    didSet {
        defaults.set(launchAtLogin, forKey: Keys.launchAtLogin.rawValue)
        loginItemSyncResult = LoginItemManager.sync(enabled: launchAtLogin)
        fire()
    }
}

@Published private(set) var loginItemSyncResult: LoginItemManager.SyncResult = .ok
```

(`LoginItemManager.SyncResult` lives in the same module — no import needed beyond what's already in scope.)

- [ ] **Step 3: Replace `GeneralPage.swift` stub**

`Sources/vibelight-app/SettingsWindow/GeneralPage.swift`:

```swift
import SwiftUI

struct GeneralPage: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsBox {
                SettingsRow(
                    "Launch at login",
                    description: launchAtLoginDescription
                ) {
                    Toggle("", isOn: Binding(
                        get: { viewModel.settings.launchAtLogin },
                        set: { viewModel.settings.launchAtLogin = $0 }
                    ))
                    .labelsHidden()
                }
                Divider().padding(.horizontal, 12)
                SettingsRow(
                    "Notify on HA errors",
                    description: "Show a macOS notification when Home Assistant rejects a request."
                ) {
                    Toggle("", isOn: Binding(
                        get: { viewModel.settings.notifyOnHAError },
                        set: { viewModel.settings.notifyOnHAError = $0 }
                    ))
                    .labelsHidden()
                }
            }
        }
    }

    private var launchAtLoginDescription: String {
        switch viewModel.settings.loginItemSyncResult {
        case .ok:
            return "Start VibeLight automatically when you sign in."
        case .notSupported:
            return "Start VibeLight automatically when you sign in. ⚠️ Login Item registration not supported for this build — drag VibeLight.app to /Applications, or use a signed build."
        case .failed(let msg):
            return "Start VibeLight automatically when you sign in. ⚠️ Failed: \(msg)"
        }
    }
}
```

- [ ] **Step 4: Verify build**

Run: `swift build`
Expected: clean.

- [ ] **Step 5: Smoke**

Launch the app, open Settings → General. Toggle "Launch at login" on and off — even for unsigned dev bundles the toggle should respond (with the ⚠️ description if registration fails). Inspect the description text to confirm the warning appears for unsigned bundles.

- [ ] **Step 6: Commit**

```bash
git add Sources/vibelight-app/Settings/LoginItemManager.swift Sources/vibelight-app/Settings/SettingsStore.swift Sources/vibelight-app/SettingsWindow/GeneralPage.swift
git commit -m "feat(app): wire Launch-at-login to SMAppService; rebuild General page"
```

---

## Task 4: `IntegrationsPage`

**Files:**
- Modify (replace stub): `Sources/vibelight-app/SettingsWindow/IntegrationsPage.swift`

Folds the old `HomeAssistantTab` (URL + token + light entity + scan) and `ClaudeCodeTab` (hook install status) into one page. Scene Pack moves to Task 7's dedicated page. Layout uses two `SettingsSection`s: "Home Assistant" and "Claude Code".

- [ ] **Step 1: Replace `IntegrationsPage.swift`**

`Sources/vibelight-app/SettingsWindow/IntegrationsPage.swift`:

```swift
import SwiftUI
import VibeBrokerNet

struct IntegrationsPage: View {
    @ObservedObject var viewModel: AppViewModel
    @SwiftUI.State private var scanning: Bool = false
    @SwiftUI.State private var discovered: [DiscoveredHA] = []
    @SwiftUI.State private var token: String = ""
    @SwiftUI.State private var entities: [String] = []
    @SwiftUI.State private var testStatus: String = ""
    @SwiftUI.State private var hookStatus: HookInstallStatus = .notInstalled
    @SwiftUI.State private var hookActionResult: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(title: "Home Assistant")
            SettingsBox {
                SettingsRow(
                    "URL",
                    description: "Address of your Home Assistant instance."
                ) {
                    HStack {
                        TextField("http://homeassistant.local:8123", text: Binding(
                            get: { viewModel.settings.haURL },
                            set: { viewModel.settings.haURL = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                        Button(scanning ? "Scanning…" : "Scan") {
                            Task { await scan() }
                        }
                        .disabled(scanning)
                    }
                }
                if !discovered.isEmpty {
                    Divider().padding(.horizontal, 12)
                    SettingsRow(
                        "Found on network",
                        description: "Click to fill the URL above."
                    ) {
                        VStack(alignment: .trailing) {
                            ForEach(discovered, id: \.id) { ha in
                                Button(ha.name) {
                                    viewModel.settings.haURL = "http://\(ha.endpoint.dropLast()):8123"
                                }
                                .buttonStyle(.link)
                            }
                        }
                    }
                }
                Divider().padding(.horizontal, 12)
                SettingsRow(
                    "Access Token",
                    description: "Long-lived access token. Stored in Keychain."
                ) {
                    SecureField("…", text: $token)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                        .onAppear { token = viewModel.settings.haToken ?? "" }
                        .onChange(of: token) { newValue in viewModel.settings.haToken = newValue }
                }
                Divider().padding(.horizontal, 12)
                SettingsRow(
                    "Test connection",
                    description: testStatus.isEmpty
                        ? "Verify VibeLight can reach Home Assistant."
                        : testStatus
                ) {
                    Button("Test") { Task { await testConnection() } }
                }
                Divider().padding(.horizontal, 12)
                SettingsRow(
                    "Light entity",
                    description: "Which Home Assistant light VibeLight drives."
                ) {
                    HStack {
                        Picker("", selection: Binding(
                            get: { viewModel.settings.haLightEntity },
                            set: { viewModel.settings.haLightEntity = $0 }
                        )) {
                            Text("Select…").tag("")
                            ForEach(entities, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        Button("Refresh") { Task { await fetchEntities() } }
                    }
                }
            }

            SettingsSectionHeader(title: "Claude Code")
            SettingsBox {
                SettingsRow(
                    "Hook status",
                    description: hookStatus == .installed
                        ? "VibeLight hooks are installed in ~/.claude/settings.json."
                        : "Not installed. Claude Code won't notify VibeLight of events."
                ) {
                    HStack {
                        Text(hookStatus == .installed ? "Installed ✓" : "Not installed")
                            .foregroundColor(hookStatus == .installed ? .green : .secondary)
                        Button(hookStatus == .installed ? "Reinstall" : "Install") {
                            do {
                                try viewModel.hookInstaller.install()
                                hookStatus = .installed
                                hookActionResult = "✓ Installed"
                            } catch {
                                hookActionResult = "✗ \(error)"
                            }
                        }
                        if hookStatus == .installed {
                            Button("Uninstall", role: .destructive) {
                                do {
                                    try viewModel.hookInstaller.uninstall()
                                    hookStatus = .notInstalled
                                    hookActionResult = "✓ Uninstalled"
                                } catch {
                                    hookActionResult = "✗ \(error)"
                                }
                            }
                        }
                    }
                }
                if !hookActionResult.isEmpty {
                    Divider().padding(.horizontal, 12)
                    SettingsRow("Last action", description: nil) {
                        Text(hookActionResult).font(.caption)
                    }
                }
            }
        }
        .onAppear {
            hookStatus = viewModel.hookInstaller.status()
            if entities.isEmpty { Task { await fetchEntities() } }
        }
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
            testStatus = "✗ URL or token missing"; return
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
            // ignore in UI
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: clean.

- [ ] **Step 3: Smoke**

Open Settings → Integrations. Verify URL field, Scan button, Token field, Test button, light entity picker, and Hook status row all appear in two grouped boxes labeled "Home Assistant" and "Claude Code".

- [ ] **Step 4: Commit**

```bash
git add Sources/vibelight-app/SettingsWindow/IntegrationsPage.swift
git commit -m "feat(app): IntegrationsPage with HA connection + Claude Code hook status"
```

---

## Task 5: `LightEffectsPage` (3 grouped subsections)

**Files:**
- Modify (replace stub): `Sources/vibelight-app/SettingsWindow/LightEffectsPage.swift`

Groups the 7 states into 3 subsections (Session / Interactions / System), each in its own grouped box. Per-state row: color picker + brightness slider + effect picker, plus a short description.

- [ ] **Step 1: Replace `LightEffectsPage.swift`**

`Sources/vibelight-app/SettingsWindow/LightEffectsPage.swift`:

```swift
import SwiftUI
import VibeBrokerCore

struct LightEffectsPage: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionBox(
                header: "Session",
                states: [.idle, .working, .done],
                description: { state in
                    switch state {
                    case .idle:    return "No agent active."
                    case .working: return "Agent is thinking or running a tool."
                    case .done:    return "Agent finished its turn."
                    default:       return ""
                    }
                }
            )
            sectionBox(
                header: "Interactions",
                states: [.waitingInput, .needsAuth],
                description: { state in
                    switch state {
                    case .waitingInput: return "Agent is waiting for your input."
                    case .needsAuth:    return "Agent needs your permission."
                    default:            return ""
                    }
                }
            )
            sectionBox(
                header: "System",
                states: [.compacting, .error],
                description: { state in
                    switch state {
                    case .compacting: return "Context window is being compressed."
                    case .error:      return "Tool call failed or agent reported an error."
                    default:          return ""
                    }
                }
            )

            HStack {
                Spacer()
                Button("Reset to defaults") { viewModel.settings.resetColors() }
            }
            .padding(.top, 16)
        }
    }

    @ViewBuilder
    private func sectionBox(header: String,
                             states: [VibeBrokerCore.State],
                             description: (VibeBrokerCore.State) -> String) -> some View {
        SettingsSectionHeader(title: header)
        SettingsBox {
            ForEach(Array(states.enumerated()), id: \.element) { idx, state in
                row(for: state, description: description(state))
                if idx < states.count - 1 { Divider().padding(.horizontal, 12) }
            }
        }
    }

    private func row(for state: VibeBrokerCore.State, description: String) -> some View {
        SettingsRow(StateAppearance.label(state), description: description) {
            HStack(spacing: 8) {
                ColorPicker("", selection: bindingForColor(state)).labelsHidden().frame(width: 36)
                Slider(value: bindingForBrightness(state), in: 1...255, step: 1).frame(width: 120)
                Text("\(Int(viewModel.settings.colors[state]?.brightness ?? 0))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 32, alignment: .trailing)
                Picker("", selection: bindingForEffect(state)) {
                    ForEach([Effect.solid, .breathe, .blink, .blinkThenSolid], id: \.self) { e in
                        Text(e.rawValue).tag(e)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
            }
        }
    }

    private func bindingForColor(_ state: VibeBrokerCore.State) -> Binding<Color> {
        Binding(
            get: {
                let rgb = viewModel.settings.colors[state]?.rgb ?? [0, 0, 0]
                return Color(red: Double(rgb[0]) / 255,
                             green: Double(rgb[1]) / 255,
                             blue: Double(rgb[2]) / 255)
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
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return [
            Int(ns.redComponent * 255),
            Int(ns.greenComponent * 255),
            Int(ns.blueComponent * 255),
        ]
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: clean. (The `Color.rgbComponents()` extension is duplicated here from the old `ColorsTab.swift`. Since the old file is deleted in Task 8, no symbol collision.)

- [ ] **Step 3: Smoke**

Open Settings → Light Effects. Should see 3 grouped boxes with section headers, each containing 2–3 rows. Each row has color swatch + brightness slider + effect picker. "Reset to defaults" button below.

- [ ] **Step 4: Commit**

```bash
git add Sources/vibelight-app/SettingsWindow/LightEffectsPage.swift
git commit -m "feat(app): LightEffectsPage with Session/Interactions/System groupings"
```

---

## Task 6: `NetworkPage`

**Files:**
- Modify (replace stub): `Sources/vibelight-app/SettingsWindow/NetworkPage.swift`

- [ ] **Step 1: Replace `NetworkPage.swift`**

`Sources/vibelight-app/SettingsWindow/NetworkPage.swift`:

```swift
import SwiftUI
import VibeBrokerNet

struct NetworkPage: View {
    @ObservedObject var viewModel: AppViewModel
    @SwiftUI.State private var checking: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(title: "Home detection")
            SettingsBox {
                SettingsRow(
                    "Status",
                    description: "VibeLight only drives your light while at home (Home Assistant reachable)."
                ) {
                    HStack(spacing: 6) {
                        Circle().fill(viewModel.isAtHome ? .green : .secondary).frame(width: 8, height: 8)
                        Text(viewModel.isAtHome ? "At home" : "Away")
                    }
                }
                if let hint = viewModel.settings.homeSSIDHint {
                    Divider().padding(.horizontal, 12)
                    SettingsRow("Last home Wi-Fi", description: "Remembered the last time HA was reachable.") {
                        Text(hint).foregroundColor(.secondary)
                    }
                }
                Divider().padding(.horizontal, 12)
                SettingsRow("Check now", description: "Force an immediate reachability probe.") {
                    Button(checking ? "Checking…" : "Check") {
                        checking = true
                        Task {
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
            }
        }
    }
}
```

- [ ] **Step 2: Verify build + smoke + commit**

Run: `swift build`
Expected: clean.

Smoke: open Settings → Network; should see one grouped box with Status, optional Wi-Fi hint, Check button.

```bash
git add Sources/vibelight-app/SettingsWindow/NetworkPage.swift
git commit -m "feat(app): NetworkPage with at-home status and check button"
```

---

## Task 7: `ScenePackPage` (extracted)

**Files:**
- Modify (replace stub): `Sources/vibelight-app/SettingsWindow/ScenePackPage.swift`

Pulls the scene pack mode + install/uninstall buttons out of the old HomeAssistantTab into their own destination. Adds an explainer at the top of the page so the user knows what scene pack mode IS.

- [ ] **Step 1: Replace `ScenePackPage.swift`**

`Sources/vibelight-app/SettingsWindow/ScenePackPage.swift`:

```swift
import SwiftUI
import VibeBrokerNet

struct ScenePackPage: View {
    @ObservedObject var viewModel: AppViewModel
    @SwiftUI.State private var sceneStatus: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("VibeLight has two ways to drive your light:")
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                bullet("Broker-emulated (default)", "VibeLight sends raw color + brightness changes to Home Assistant in real time. Zero HA setup.")
                bullet("Scene pack (advanced)", "VibeLight installs 7 named scenes in HA and only triggers them by name. Less network traffic, lets you customize effects in HA's own UI.")
            }
            .padding(.top, 6)

            SettingsSectionHeader(title: "Mode")
            SettingsBox {
                SettingsRow("Light effect mode", description: nil) {
                    Picker("", selection: Binding(
                        get: { viewModel.settings.renderMode },
                        set: { viewModel.settings.renderMode = $0 }
                    )) {
                        Text("Broker-emulated").tag(SettingsStore.RenderMode.brokerEmulated)
                        Text("Scene pack").tag(SettingsStore.RenderMode.scenePack)
                    }
                    .labelsHidden()
                    .pickerStyle(.radioGroup)
                }
            }

            SettingsSectionHeader(title: "Scene pack")
            SettingsBox {
                SettingsRow(
                    "Install",
                    description: "Creates 7 scenes named `scene.vibelight_*` in Home Assistant."
                ) {
                    Button("Install") { Task { await installScenePack() } }
                }
                Divider().padding(.horizontal, 12)
                SettingsRow(
                    "Uninstall",
                    description: "Removes the VibeLight scenes from Home Assistant."
                ) {
                    Button("Uninstall", role: .destructive) { Task { await uninstallScenePack() } }
                }
                if !sceneStatus.isEmpty {
                    Divider().padding(.horizontal, 12)
                    SettingsRow("Last action", description: nil) {
                        Text(sceneStatus).font(.caption)
                    }
                }
            }
        }
    }

    private func bullet(_ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout).bold()
                Text(desc).font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func installScenePack() async {
        guard let url = URL(string: viewModel.settings.haURL),
              let t = viewModel.settings.haToken,
              let cfg = try? ConfigBuilder.build(from: viewModel.settings) else {
            sceneStatus = "✗ Settings incomplete"; return
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
            sceneStatus = "✗ Settings incomplete"; return
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

- [ ] **Step 2: Verify build + smoke + commit**

Run: `swift build`
Expected: clean.

Smoke: open Settings → Scene Pack. Should see the explainer bullets, mode radio group, install/uninstall buttons.

```bash
git add Sources/vibelight-app/SettingsWindow/ScenePackPage.swift
git commit -m "feat(app): ScenePackPage extracted from old HomeAssistantTab"
```

---

## Task 8: `DiagnosticsPage` + `AboutPage` + delete old `*Tab` files

**Files:**
- Modify (replace stub): `Sources/vibelight-app/SettingsWindow/DiagnosticsPage.swift`
- Modify (replace stub): `Sources/vibelight-app/SettingsWindow/AboutPage.swift`
- Delete: `Sources/vibelight-app/SettingsWindow/GeneralTab.swift`
- Delete: `Sources/vibelight-app/SettingsWindow/HomeAssistantTab.swift`
- Delete: `Sources/vibelight-app/SettingsWindow/ColorsTab.swift`
- Delete: `Sources/vibelight-app/SettingsWindow/NetworkTab.swift`
- Delete: `Sources/vibelight-app/SettingsWindow/ClaudeCodeTab.swift`
- Delete: `Sources/vibelight-app/SettingsWindow/AdvancedTab.swift`

- [ ] **Step 1: Replace `DiagnosticsPage.swift`**

`Sources/vibelight-app/SettingsWindow/DiagnosticsPage.swift`:

```swift
import SwiftUI

struct DiagnosticsPage: View {
    @ObservedObject var viewModel: AppViewModel
    @SwiftUI.State private var showResetConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(title: "Broker")
            SettingsBox {
                SettingsRow(
                    "Port",
                    description: "Local HTTP port VibeLight's broker listens on. Restart required."
                ) {
                    TextField("17345", value: Binding(
                        get: { viewModel.settings.brokerPort },
                        set: { viewModel.settings.brokerPort = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                }
                Divider().padding(.horizontal, 12)
                SettingsRow(
                    "Default pause duration",
                    description: "Seconds the menubar Pause shortcut defaults to."
                ) {
                    TextField("1800", value: Binding(
                        get: { viewModel.settings.defaultPauseSeconds },
                        set: { viewModel.settings.defaultPauseSeconds = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                }
            }

            SettingsSectionHeader(title: "Logs & state")
            SettingsBox {
                SettingsRow(
                    "Logs folder",
                    description: "VibeLight writes diagnostics here."
                ) {
                    Button("Open") {
                        let path = FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent("Library/Logs/VibeLight")
                        try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(path)
                    }
                }
                Divider().padding(.horizontal, 12)
                SettingsRow(
                    "Reset all settings",
                    description: "Removes UserDefaults values and deletes the HA token from Keychain. Restarts onboarding."
                ) {
                    Button("Reset…", role: .destructive) { showResetConfirm = true }
                        .confirmationDialog(
                            "Reset all VibeLight settings? Your HA token will be removed from Keychain.",
                            isPresented: $showResetConfirm
                        ) {
                            Button("Reset", role: .destructive) { viewModel.settings.resetAll() }
                            Button("Cancel", role: .cancel) {}
                        }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Replace `AboutPage.swift`**

`Sources/vibelight-app/SettingsWindow/AboutPage.swift`:

```swift
import SwiftUI

struct AboutPage: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.yellow)
                VStack(alignment: .leading) {
                    Text("VibeLight").font(.title).bold()
                    Text("Version \(version)").foregroundColor(.secondary)
                }
            }

            SettingsBox {
                SettingsRow("Source", description: "VibeLight is open source.") {
                    Button("View on GitHub") {
                        // Repo URL is filled in once the project is pushed; for now this is a placeholder.
                        // P5 will populate from Bundle.main.infoDictionary if the homepage URL is set.
                    }
                    .disabled(true)
                }
                Divider().padding(.horizontal, 12)
                SettingsRow("License", description: "MIT.") {
                    EmptyView()
                }
            }

            Text("Built with Swift, SwiftUI, and Network.framework. Zero third-party dependencies.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
    }
}
```

- [ ] **Step 3: Delete the 6 old tab files**

```bash
cd "/Users/ryekee/workshop/P.A.R.A/0. Project/Gadgets/VibeLight"
git rm Sources/vibelight-app/SettingsWindow/GeneralTab.swift
git rm Sources/vibelight-app/SettingsWindow/HomeAssistantTab.swift
git rm Sources/vibelight-app/SettingsWindow/ColorsTab.swift
git rm Sources/vibelight-app/SettingsWindow/NetworkTab.swift
git rm Sources/vibelight-app/SettingsWindow/ClaudeCodeTab.swift
git rm Sources/vibelight-app/SettingsWindow/AdvancedTab.swift
```

- [ ] **Step 4: Verify build + smoke**

Run: `swift build`
Expected: clean. All references to the deleted tab types should have been removed by Tasks 2–7.

Smoke: open Settings → walk all 7 destinations. Each should render its real page. No "TabView" remnants.

- [ ] **Step 5: Commit**

```bash
git add Sources/vibelight-app/SettingsWindow
git commit -m "feat(app): DiagnosticsPage + AboutPage; remove old tab files"
```

---

## Task 9: `TranscriptDiscovery` actor

**Files:**
- Create: `Sources/VibeBrokerNet/TranscriptDiscovery.swift`
- Create: `Tests/VibeBrokerNetTests/TranscriptDiscoveryTests.swift`

`TranscriptDiscovery.findRecentSessionIDs(root:cutoff:limit:)` enumerates `~/.claude/projects/*/*.jsonl` and returns up to `limit` session ids whose file mtime is newer than `cutoff`. Pure file-listing — no JSONL content parsing in P4.

- [ ] **Step 1: Write failing tests**

`Tests/VibeBrokerNetTests/TranscriptDiscoveryTests.swift`:

```swift
import XCTest
@testable import VibeBrokerNet

final class TranscriptDiscoveryTests: XCTestCase {
    private func tempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibelight-disc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func touch(_ url: URL, mtime: Date) throws {
        FileManager.default.createFile(atPath: url.path, contents: Data())
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
    }

    func testFindsRecentSessionIDs() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("-Users-me-projA")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let now = Date()
        try touch(project.appendingPathComponent("abc-123.jsonl"), mtime: now)
        try touch(project.appendingPathComponent("def-456.jsonl"), mtime: now.addingTimeInterval(-60))

        let discovery = TranscriptDiscovery()
        let ids = try await discovery.findRecentSessionIDs(
            root: root, cutoff: now.addingTimeInterval(-3600), limit: 40
        )

        XCTAssertEqual(Set(ids), Set(["abc-123", "def-456"]))
    }

    func testIgnoresFilesOlderThanCutoff() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("-foo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let now = Date()
        try touch(project.appendingPathComponent("fresh.jsonl"), mtime: now)
        try touch(project.appendingPathComponent("stale.jsonl"), mtime: now.addingTimeInterval(-48 * 3600))

        let discovery = TranscriptDiscovery()
        let ids = try await discovery.findRecentSessionIDs(
            root: root, cutoff: now.addingTimeInterval(-24 * 3600), limit: 40
        )

        XCTAssertEqual(ids, ["fresh"])
    }

    func testRespectsLimit() async throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("-foo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let now = Date()
        for i in 0..<10 {
            try touch(project.appendingPathComponent("session-\(i).jsonl"),
                      mtime: now.addingTimeInterval(TimeInterval(-i)))
        }

        let discovery = TranscriptDiscovery()
        let ids = try await discovery.findRecentSessionIDs(
            root: root, cutoff: now.addingTimeInterval(-3600), limit: 3
        )

        XCTAssertEqual(ids.count, 3)
        // Most-recent first: session-0, session-1, session-2.
        XCTAssertEqual(ids, ["session-0", "session-1", "session-2"])
    }

    func testReturnsEmptyWhenRootMissing() async throws {
        let discovery = TranscriptDiscovery()
        let nope = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString)")
        let ids = try await discovery.findRecentSessionIDs(
            root: nope, cutoff: Date().addingTimeInterval(-3600), limit: 40
        )
        XCTAssertTrue(ids.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test --filter VibeBrokerNetTests.TranscriptDiscoveryTests`
Expected: FAIL — `TranscriptDiscovery` undefined.

- [ ] **Step 3: Implement `TranscriptDiscovery.swift`**

`Sources/VibeBrokerNet/TranscriptDiscovery.swift`:

```swift
import Foundation

public actor TranscriptDiscovery {
    public init() {}

    /// Returns session ids (filename stems) for `*.jsonl` files under
    /// `<root>/<project-dir>/<session-id>.jsonl` whose modification date is
    /// newer than `cutoff`, sorted most-recent first, capped at `limit`.
    public func findRecentSessionIDs(root: URL, cutoff: Date, limit: Int) async throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }

        struct Candidate {
            let id: String
            let mtime: Date
        }
        var candidates: [Candidate] = []

        // Each subdirectory under root is a project. We only descend one level.
        let projects = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for project in projects {
            let isDir = (try? project.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            let files = (try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files where file.pathExtension == "jsonl" {
                guard let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                      mtime >= cutoff else { continue }
                let id = file.deletingPathExtension().lastPathComponent
                candidates.append(Candidate(id: id, mtime: mtime))
            }
        }

        candidates.sort { $0.mtime > $1.mtime }
        return candidates.prefix(limit).map(\.id)
    }

    /// Default Claude Code transcript root: `~/.claude/projects`.
    public static func defaultClaudeRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter VibeBrokerNetTests.TranscriptDiscoveryTests`
Expected: PASS — 4 tests.

Run: `swift test`
Expected: 81 tests pass total (77 + 4).

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeBrokerNet/TranscriptDiscovery.swift Tests/VibeBrokerNetTests/TranscriptDiscoveryTests.swift
git commit -m "feat(net): add TranscriptDiscovery for Claude Code session cold-start"
```

---

## Task 10: `BrokerHost.discoverHistoricalSessions` + AppViewModel hookup

**Files:**
- Modify: `Sources/VibeBrokerNet/BrokerHost.swift`
- Modify: `Sources/vibelight-app/AppViewModel.swift`

`BrokerHost.discoverHistoricalSessions(root:cutoff:limit:)` calls `TranscriptDiscovery.findRecentSessionIDs(...)`, then for each id synthesizes a `SessionStart` `HookEvent` and feeds it to `EventRouter.handle(_:)`. The router applies the transition, the session lands in SessionStore as `.idle`. Any subsequent real hook event from Claude Code transitions it normally.

- [ ] **Step 1: Add method to `BrokerHost`**

In `Sources/VibeBrokerNet/BrokerHost.swift`, add inside the actor (e.g. after `testRender`):

```swift
public func discoverHistoricalSessions(
    root: URL = TranscriptDiscovery.defaultClaudeRoot(),
    cutoff: Date = Date().addingTimeInterval(-24 * 3600),
    limit: Int = 40
) async -> Int {
    let discovery = TranscriptDiscovery()
    let ids: [String]
    do {
        ids = try await discovery.findRecentSessionIDs(root: root, cutoff: cutoff, limit: limit)
    } catch {
        return 0
    }
    for id in ids {
        let event = HookEvent(
            hookName: .sessionStart,
            sessionId: id,
            cwd: nil,
            toolResponseIsError: false,
            notificationMessage: nil
        )
        await store.handle(event)
    }
    return ids.count
}
```

This bypasses the HTTP layer and inserts directly into the store. The observer is NOT invoked for these synthetic events — they're just bootstrap state. (If you want the menubar to show "Sessions: 3" on launch, that's already reflected via the 1 Hz session-refresh task.)

- [ ] **Step 2: Wire from `AppViewModel.bootstrap`**

In `Sources/vibelight-app/AppViewModel.swift`, inside `bootstrap()` after `try await host.start()` and before `self.startSessionRefresh()`, insert:

```swift
let recovered = await host.discoverHistoricalSessions()
if recovered > 0 {
    // For visibility; logging at this layer is `print` until we add os.Logger.
    print("VibeLight: recovered \(recovered) historical Claude Code sessions")
}
```

- [ ] **Step 3: Verify build**

Run: `swift build`
Expected: clean.

Run: `swift test`
Expected: 81 tests pass — no regressions.

- [ ] **Step 4: Manual smoke**

```bash
# Quit the existing app.
pkill -INT -f VibeLight.app/Contents/MacOS/VibeLight 2>/dev/null || true
sleep 1

# Rebuild + relaunch.
./scripts/bundle.sh
open build/VibeLight.app
sleep 4

# Push an event for a synthetic session that the bootstrap would have recovered.
# (In real usage, Claude Code transcripts at ~/.claude/projects/*/*.jsonl populate this.)
echo '{"session_id":"alice","cwd":"/repo/a"}' | curl -s -X POST \
  -H 'Content-Type: application/json' --data-binary @- \
  'http://127.0.0.1:17345/event?hook=UserPromptSubmit'

sleep 1
curl -s http://127.0.0.1:17345/state | python3 -m json.tool
```

Expected: the state response shows the recovered sessions (if any `.jsonl` files exist under `~/.claude/projects/*/`) plus the synthetic `alice` you just pushed.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeBrokerNet/BrokerHost.swift Sources/vibelight-app/AppViewModel.swift
git commit -m "feat(app): cold-start historical Claude Code sessions via TranscriptDiscovery"
```

---

## Task 11: P4 smoke README + final .app build

**Files:**
- Create: `Resources/README-p4-smoke.md`

- [ ] **Step 1: Write the smoke README**

`Resources/README-p4-smoke.md`:

````markdown
# VibeLight P4 — Settings refactor + cold-start smoke

## 1. Build

```bash
./scripts/bundle.sh
```

## 2. Open Settings

Launch the app, click menubar icon, click "Settings…".

Expected layout: sidebar on the left with three sections —

- (top, no header): **General**, **Integrations**, **Light Effects**, **Network**
- **Advanced**: **Scene Pack**, **Diagnostics**
- **VibeLight**: **About**

Each sidebar row has a small colored icon glyph. Click each one in turn:

| Destination | Should show |
|---|---|
| General | Two toggles in a grouped box: Launch at login (with warning if unsigned) + Notify on HA errors |
| Integrations | HA URL + Scan + Token + Test + Light entity + Refresh, then Claude Code hook status |
| Light Effects | Three grouped sections (Session, Interactions, System), 2–3 rows each, color/brightness/effect per row, Reset button |
| Network | Status row (At home / Away), optional Wi-Fi hint, Check button |
| Scene Pack | Two-bullet explainer, mode radio group, Install/Uninstall buttons |
| Diagnostics | Broker port + default pause field; Open logs folder; Reset all settings |
| About | Version, source link (disabled placeholder), license |

## 3. Try changing a color

Light Effects → click the color swatch next to "Working" → pick a different color. The menubar icon should NOT change yet (state is still idle), but pushing a fake event will use the new color:

```bash
echo '{"session_id":"x"}' | curl -s -X POST \
  -H 'Content-Type: application/json' --data-binary @- \
  'http://127.0.0.1:17345/event?hook=UserPromptSubmit'
```

Menubar icon → your new working color. (Settings auto-reload — no restart.)

## 4. Verify Launch-at-login behavior

General → toggle Launch at login on.

- For a **signed app** placed in /Applications: the toggle persists and a Login Item appears in System Settings → General → Login Items.
- For an **unsigned dev build** (our `./scripts/bundle.sh` output): the description text under the toggle will warn "Login Item registration not supported for this build." The toggle still flips the UserDefaults value; it just doesn't register the system item.

## 5. Verify cold-start transcript discovery

If you have any `*.jsonl` files under `~/.claude/projects/*/`, quitting and relaunching the app should auto-populate the Sessions submenu with those session ids (in state Idle). Check via:

```bash
ls ~/.claude/projects/*/*.jsonl 2>/dev/null | head -5
# Then:
curl -s http://127.0.0.1:17345/state | python3 -m json.tool
```

The `sessions` map should contain the recovered ids.

## 6. Quit

Menubar → Quit. Within ~1 second:

```bash
pgrep -f VibeLight   # should print nothing
```
````

- [ ] **Step 2: Final build + smoke run**

```bash
./scripts/bundle.sh
open build/VibeLight.app
sleep 3
curl -s http://127.0.0.1:17345/health
pkill -INT -f VibeLight.app/Contents/MacOS/VibeLight || true
```

Expected: bundle builds, app launches, broker responds 200 OK.

- [ ] **Step 3: Tag the milestone**

```bash
git add Resources/README-p4-smoke.md
git commit -m "docs: P4 smoke README"
git tag p4-settings-refactor
```

---

## Final verification

- [ ] **Full test suite**

```bash
swift test
```

Expected: 81 tests pass.

- [ ] **Visual walkthrough**

Follow `Resources/README-p4-smoke.md` interactively. Confirm every destination renders the right page in the new sidebar style, the color you pick in Light Effects actually applies on the next hook event, and Launch-at-login surfaces a warning for unsigned builds.

---

## P4 done. What's next?

P4 brings the Settings UI in line with modern macOS conventions and recovers historical Claude Code sessions on app launch.

**Open follow-ups for P5:**
- Codex CLI hook installer (`~/.codex/config.toml`, `[features].hooks = true`, hook entries for `SessionStart`/`UserPromptSubmit`/`Stop`)
- Codex Desktop App JSON-RPC subprocess (`codex app-server`) consumed via newline-delimited JSON-RPC for `thread/status/changed`, `turn/completed`
- Terminal pane jump-back (env-var capture in hook script: `TERM_PROGRAM`, `CMUX_SURFACE_ID`, `ZELLIJ_PANE_ID`, `ITERM_SESSION_ID`)
- Two-poll liveness threshold for session removal (replace blanket 5-minute TTL)
- Menubar icon animations to mirror the actual light effect
- About page: actual GitHub URL once the repo is public
- Code signing / notarization (would also fix SMAppService for distributed builds)
