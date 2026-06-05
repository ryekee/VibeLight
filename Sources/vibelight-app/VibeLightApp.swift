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
            OnboardingRoot(appViewModel: viewModel)
        }
        .windowResizability(.contentMinSize)
    }
}

/// Owns the onboarding view model with `@StateObject` so it is created
/// exactly once and survives scene re-evaluations. Creating it inline in
/// the `Window` builder instead rebuilt it on every `AppViewModel` publish
/// (e.g. `bootstrap()` setting `listening`/`isAtHome` once a light is
/// chosen), snapping the wizard back to its first page.
private struct OnboardingRoot: View {
    @ObservedObject var appViewModel: AppViewModel
    @StateObject private var onboardingViewModel: OnboardingViewModel

    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
        _onboardingViewModel = StateObject(
            wrappedValue: OnboardingViewModel(appViewModel: appViewModel)
        )
    }

    var body: some View {
        if appViewModel.needsOnboarding {
            OnboardingWindow(viewModel: onboardingViewModel)
        } else {
            EmptyView()
        }
    }
}
