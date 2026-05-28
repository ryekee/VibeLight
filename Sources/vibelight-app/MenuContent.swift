import SwiftUI
import VibeBrokerCore

struct MenuContent: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        statusSection
        Divider()
        sessionsSection
        pauseSection
        testSection
        Divider()
        Button("Show Sessions Window…") { openWindow(id: "sessions") }
        Button("Settings…")            { openWindow(id: "settings") }
        Divider()
        Button("Quit VibeLight") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusSection: some View {
        Group {
            if viewModel.needsOnboarding {
                Text("Setup required")
                Button("Continue setup…") { openWindow(id: "onboarding") }
            } else if let err = viewModel.lastError {
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

    private var sessionsSection: some View {
        Menu("Sessions (\(viewModel.sessions.count))") {
            if viewModel.sessions.isEmpty {
                Text("No active sessions").foregroundColor(.secondary)
            } else {
                ForEach(viewModel.sessions, id: \.id) { rec in
                    Text("\(StateAppearance.label(rec.state)) — \(rec.cwd ?? String(rec.id.prefix(8)))")
                }
            }
        }
    }

    private var testSection: some View {
        Menu("Test light effect") {
            ForEach(VibeBrokerCore.State.allCases, id: \.self) { state in
                Button(StateAppearance.label(state)) { viewModel.testRender(state) }
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
