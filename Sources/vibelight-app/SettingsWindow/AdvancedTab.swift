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
