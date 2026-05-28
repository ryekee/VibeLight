import SwiftUI
import VibeBrokerNet

struct NetworkConfirmPage: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var probing: Bool = false
    @State private var reachable: Bool? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Confirm home network").font(.headline)
            Text("VibeLight will only drive your light when Home Assistant is reachable. We use this connection as the 'at home' signal.")
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(probing ? "Checking…" : "Check Home Assistant now") {
                    probing = true
                    Task {
                        guard let url = URL(string: viewModel.settings.haURL),
                              let token = viewModel.settings.haToken else {
                            reachable = false; probing = false; return
                        }
                        let probe = HomeReachability.haProbe(baseURL: url, token: token)
                        reachable = await probe()
                        probing = false
                        viewModel.canAdvance = (reachable == true)
                    }
                }
                .disabled(probing)
                if let r = reachable {
                    Text(r ? "✓ Reachable" : "✗ Not reachable")
                        .foregroundColor(r ? .green : .red)
                }
            }

            if reachable == true {
                Text("Your current Wi-Fi will be remembered as your home network hint.")
                    .foregroundColor(.secondary).font(.caption).padding(.top, 8)
            }

            Spacer()
        }
        .onAppear {
            viewModel.canAdvance = false
        }
    }
}
