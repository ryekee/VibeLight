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
