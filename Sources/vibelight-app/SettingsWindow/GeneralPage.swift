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
