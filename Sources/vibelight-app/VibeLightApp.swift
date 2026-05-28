import SwiftUI

@main
struct VibeLightApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(viewModel: viewModel)
        } label: {
            Image(systemName: "circle.fill")
                .foregroundColor(StateAppearance.color(viewModel.effectiveState))
        }
        .menuBarExtraStyle(.menu)
    }
}
