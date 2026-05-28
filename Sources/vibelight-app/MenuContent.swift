import SwiftUI
import VibeBrokerCore

struct MenuContent: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        statusSection
        Divider()
        Button("Quit VibeLight") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusSection: some View {
        Group {
            if let err = viewModel.lastError {
                Text("⚠️ \(err)")
            } else if !viewModel.listening {
                Text("Starting broker…")
            } else {
                Text(StateAppearance.label(viewModel.effectiveState))
                Text("Sessions: \(viewModel.sessions.count)")
                    .font(.caption)
            }
        }
    }
}
