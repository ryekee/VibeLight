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
