import SwiftUI

@main
struct VibeLightApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(viewModel: viewModel)
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.menu)

        Window("VibeLight Sessions", id: "sessions") {
            SessionsWindow(viewModel: viewModel)
        }
        .windowResizability(.contentMinSize)

        Window("VibeLight Settings", id: "settings") {
            SettingsWindow(viewModel: viewModel)
        }
        .windowResizability(.contentSize)

        Window("VibeLight Onboarding", id: "onboarding") {
            if viewModel.needsOnboarding {
                OnboardingWindow(viewModel: OnboardingViewModel(appViewModel: viewModel))
            } else {
                EmptyView()
            }
        }
        .windowResizability(.contentMinSize)
    }
}
