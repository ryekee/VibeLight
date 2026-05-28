import SwiftUI

struct HAConnectionPage: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var tokenInput: String = ""
    @State private var probing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scan local network").font(.headline)
            if viewModel.discovered.isEmpty {
                Text("Searching for Home Assistant on this network…")
                    .foregroundColor(.secondary).font(.caption)
            } else {
                ForEach(viewModel.discovered, id: \.id) { ha in
                    Button {
                        viewModel.settings.haURL = "http://\(ha.endpoint.dropLast()):8123"
                    } label: {
                        HStack {
                            Image(systemName: "house.fill")
                            Text(ha.name)
                            Spacer()
                            Text(ha.endpoint).foregroundColor(.secondary).font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().padding(.vertical, 4)

            Text("Or enter URL manually").font(.headline)
            TextField("http://homeassistant.local:8123", text: Binding(
                get: { viewModel.settings.haURL },
                set: { viewModel.settings.haURL = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            Text("Access Token").font(.headline).padding(.top, 8)
            SecureField("Long-lived access token", text: $tokenInput)
                .textFieldStyle(.roundedBorder)
                .onAppear { tokenInput = viewModel.settings.haToken ?? "" }
                .onChange(of: tokenInput) { newValue in
                    viewModel.settings.haToken = newValue
                }

            HStack {
                Button(probing ? "Testing…" : "Test connection") {
                    probing = true
                    Task {
                        await viewModel.testHAConnection()
                        probing = false
                        viewModel.canAdvance = (viewModel.lastError == nil)
                    }
                }
                .disabled(probing)
                if let err = viewModel.lastError {
                    Text(err).foregroundColor(.red).font(.caption)
                }
            }
            Spacer()
        }
        .onAppear {
            viewModel.canAdvance = false
            viewModel.startDiscovery()
        }
        .onDisappear {
            viewModel.stopDiscovery()
        }
    }
}
