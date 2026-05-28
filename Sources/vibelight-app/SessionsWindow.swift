import SwiftUI
import VibeBrokerCore

// SessionRecord has id: String already; adding Identifiable conformance here
// so Table(_ data:) can use it without modifying VibeBrokerCore.
extension SessionRecord: Identifiable {}

struct SessionsWindow: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("VibeLight Sessions").font(.headline)
                Spacer()
                Text(viewModel.listening ? "Listening" : "Stopped")
                    .foregroundColor(viewModel.listening ? .green : .red)
            }
            Divider()
            if viewModel.sessions.isEmpty {
                Text("No active sessions").foregroundColor(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(viewModel.sessions) {
                    TableColumn("Session ID") { rec in Text(String(rec.id.prefix(8))) }
                    TableColumn("State")      { rec in Text(StateAppearance.label(rec.state)) }
                    TableColumn("Since")      { rec in Text(rec.since.formatted(date: .omitted, time: .shortened)) }
                    TableColumn("CWD")        { rec in Text(rec.cwd ?? "—") }
                }
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 240)
    }
}
