import SwiftUI
import VibeBrokerNet

struct HomeAssistantTab: View {
    @ObservedObject var viewModel: AppViewModel
    @SwiftUI.State private var scanning: Bool = false
    @SwiftUI.State private var discovered: [DiscoveredHA] = []
    @SwiftUI.State private var token: String = ""
    @SwiftUI.State private var entities: [String] = []
    @SwiftUI.State private var testStatus: String = ""
    @SwiftUI.State private var sceneStatus: String = ""

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
                    .onChange(of: token) { newValue in viewModel.settings.haToken = newValue }
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
