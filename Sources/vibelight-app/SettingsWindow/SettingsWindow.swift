import SwiftUI

struct SettingsWindow: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        TabView {
            GeneralTab(viewModel: viewModel)
                .tabItem { Label("General", systemImage: "gear") }
            HomeAssistantTab(viewModel: viewModel)
                .tabItem { Label("Home Assistant", systemImage: "house") }
            ColorsTab(viewModel: viewModel)
                .tabItem { Label("Colors", systemImage: "paintpalette") }
            NetworkTab(viewModel: viewModel)
                .tabItem { Label("Network", systemImage: "wifi") }
            ClaudeCodeTab(viewModel: viewModel)
                .tabItem { Label("Claude Code", systemImage: "terminal") }
            AdvancedTab(viewModel: viewModel)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 560, height: 420)
        .padding()
    }
}
