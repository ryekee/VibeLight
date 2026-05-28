import SwiftUI

/// Dedicated view for the menubar icon so SwiftUI subscribes the @ObservedObject
/// properly — putting state-dependent content directly in MenuBarExtra's `label:`
/// closure does not always refresh on @Published changes.
///
/// `.symbolRenderingMode(.palette)` is required because SF Symbols in the macOS
/// menu bar default to template rendering, which makes the system override any
/// `.foregroundColor` / `.foregroundStyle`.
struct MenuBarLabel: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Image(systemName: "circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(StateAppearance.color(viewModel.effectiveState))
    }
}
