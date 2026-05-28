import SwiftUI
import VibeBrokerCore

struct MenuContent: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        statusSection
        Divider()
        pauseSection
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

    private var pauseSection: some View {
        Group {
            if let until = viewModel.pauseUntil {
                Text("Paused until \(formatted(until))")
                Button("Resume") { viewModel.resume() }
            } else {
                Menu("Pause") {
                    Button(PauseDuration.thirtyMinutes.label) { viewModel.pauseFor(.thirtyMinutes) }
                    Button(PauseDuration.oneHour.label)      { viewModel.pauseFor(.oneHour) }
                    Button(PauseDuration.untilTomorrow.label){ viewModel.pauseFor(.untilTomorrow) }
                }
            }
        }
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }
}
