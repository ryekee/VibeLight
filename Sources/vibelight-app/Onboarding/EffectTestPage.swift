import SwiftUI
import VibeBrokerCore

private typealias AgentState = VibeBrokerCore.State

struct EffectTestPage: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @SwiftUI.State private var selected: AgentState = .working

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test light effects").font(.headline)
            Text("Click each state to verify the light responds as expected. The broker must be running — finish this wizard if it isn't yet.")
                .foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(AgentState.allCases, id: \.self) { state in
                    Button(StateAppearance.label(state)) {
                        selected = state
                        viewModel.appViewModel.testRender(state)
                    }
                    .buttonStyle(.bordered)
                    .tint(selected == state ? StateAppearance.color(state) : .accentColor)
                }
            }
            .padding(.vertical, 8)

            Text("Currently testing: \(StateAppearance.label(selected))")
                .foregroundColor(.secondary)

            Spacer()
        }
        .onAppear { viewModel.canAdvance = true }
    }
}
