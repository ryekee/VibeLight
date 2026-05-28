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
