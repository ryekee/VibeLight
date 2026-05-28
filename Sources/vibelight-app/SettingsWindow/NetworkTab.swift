import SwiftUI
import VibeBrokerNet

struct NetworkTab: View {
    @ObservedObject var viewModel: AppViewModel
    @SwiftUI.State private var checking: Bool = false

    var body: some View {
        Form {
            HStack {
                Text("Status:")
                Spacer()
                Text(viewModel.isAtHome ? "At home" : "Away")
                    .foregroundColor(viewModel.isAtHome ? .green : .secondary)
            }

            if let hint = viewModel.settings.homeSSIDHint {
                HStack {
                    Text("Last home Wi-Fi:")
                    Spacer()
                    Text(hint).foregroundColor(.secondary)
                }
            }

            HStack {
                Button(checking ? "Checking…" : "Check now") {
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
            Spacer()
        }
        .padding()
    }
}
