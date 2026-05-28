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
            SettingsPlaceholderWindow()
        }
        .windowResizability(.contentSize)
    }
}
