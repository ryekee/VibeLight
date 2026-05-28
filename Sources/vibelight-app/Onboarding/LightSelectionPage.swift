import SwiftUI

struct LightSelectionPage: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var loading: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a light entity").font(.headline)
            Text("VibeLight will drive this light to reflect your agent's state.")
                .foregroundColor(.secondary).font(.caption)

            if loading {
                ProgressView("Loading lights…")
            } else if viewModel.lightEntities.isEmpty {
                VStack {
                    Text("No lights found. Make sure your HA token has access.")
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        Task { await refresh() }
                    }
                }
            } else {
                Picker("Light", selection: Binding(
                    get: { viewModel.settings.haLightEntity },
                    set: { viewModel.settings.haLightEntity = $0 }
                )) {
                    Text("Select…").tag("")
                    ForEach(viewModel.lightEntities, id: \.self) { ent in
                        Text(ent).tag(ent)
                    }
                }
                .pickerStyle(.menu)
            }
            Spacer()
        }
        .onAppear {
            Task { await refresh() }
        }
        .onChange(of: viewModel.settings.haLightEntity) { newValue in
            viewModel.canAdvance = !newValue.isEmpty
        }
    }

    private func refresh() async {
        loading = true
        await viewModel.fetchLightEntities()
        loading = false
        viewModel.canAdvance = !viewModel.settings.haLightEntity.isEmpty
    }
}
