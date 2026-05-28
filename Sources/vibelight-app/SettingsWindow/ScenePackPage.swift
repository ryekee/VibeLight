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
