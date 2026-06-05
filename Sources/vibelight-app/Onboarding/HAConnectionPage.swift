import SwiftUI

struct HAConnectionPage: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var tokenInput: String = ""
    @State private var probing: Bool = false
    @State private var testPassed: Bool = false

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
                    invalidateTest()
                }

            HStack {
                Button(probing ? "Testing…" : "Test connection") {
                    probing = true
                    testPassed = false
                    Task {
                        await viewModel.testHAConnection()
                        probing = false
                        let ok = (viewModel.lastError == nil)
                        viewModel.canAdvance = ok
                        testPassed = ok
                    }
                }
                .disabled(probing)
                if let err = viewModel.lastError {
                    Label(err, systemImage: "xmark.circle.fill")
                        .foregroundColor(.red).font(.caption)
                } else if testPassed {
                    Label("Connected — click Next to continue", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green).font(.caption)
                }
            }
            Spacer()
        }
        // Editing the URL invalidates a prior successful test so the user
        // can't advance with credentials that were never re-verified.
        // (Token edits are handled in the SecureField's onChange above.)
        .onChange(of: viewModel.settings.haURL) { _ in invalidateTest() }
        .onAppear {
            viewModel.canAdvance = false
            viewModel.startDiscovery()
        }
        .onDisappear {
            viewModel.stopDiscovery()
        }
    }

    /// Reset a prior "Connected" result whenever the URL or token changes,
    /// forcing a fresh "Test connection" before Next re-enables.
    private func invalidateTest() {
        testPassed = false
        viewModel.canAdvance = false
        viewModel.lastError = nil
    }
}
