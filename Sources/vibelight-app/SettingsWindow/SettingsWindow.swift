import SwiftUI

struct SettingsWindow: View {
    @ObservedObject var viewModel: AppViewModel
    @SwiftUI.State private var selection: SettingsDestination? = .general

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, minHeight: 480)
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ForEach(SettingsDestination.allCases.filter { $0.group == nil }) { dest in
                    sidebarRow(dest)
                }
            }
            Section("Advanced") {
                ForEach(SettingsDestination.allCases.filter { $0.group == "Advanced" }) { dest in
                    sidebarRow(dest)
                }
            }
            Section("VibeLight") {
                ForEach(SettingsDestination.allCases.filter { $0.group == "VibeLight" }) { dest in
                    sidebarRow(dest)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }

    private func sidebarRow(_ destination: SettingsDestination) -> some View {
        Label {
            Text(destination.label)
        } icon: {
            Image(systemName: destination.systemImage)
                .frame(width: 20, height: 20)
                .foregroundColor(.white)
                .background(destination.tint)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .tag(destination)
    }

    @ViewBuilder
    private var detail: some View {
        let dest = selection ?? .general
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsPageHeader(destination: dest)
                pageContent(for: dest)
                Spacer(minLength: 24)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func pageContent(for destination: SettingsDestination) -> some View {
        switch destination {
        case .general:      GeneralPage(viewModel: viewModel)
        case .integrations: IntegrationsPage(viewModel: viewModel)
        case .lightEffects: LightEffectsPage(viewModel: viewModel)
        case .network:      NetworkPage(viewModel: viewModel)
        case .scenePack:    ScenePackPage(viewModel: viewModel)
        case .diagnostics:  DiagnosticsPage(viewModel: viewModel)
        case .about:        AboutPage()
        }
    }
}
