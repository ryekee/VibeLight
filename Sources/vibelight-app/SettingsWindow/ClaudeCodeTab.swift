import SwiftUI

struct ClaudeCodeTab: View {
    @ObservedObject var viewModel: AppViewModel
    @SwiftUI.State private var status: HookInstallStatus = .notInstalled
    @SwiftUI.State private var actionResult: String = ""

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
