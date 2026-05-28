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
