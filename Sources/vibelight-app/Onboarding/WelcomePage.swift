import SwiftUI

struct WelcomePage: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            Text("Welcome to VibeLight").font(.title).bold()
            Text("VibeLight reflects your AI agent's state on a Home Assistant–controlled light. Setup takes about 2 minutes.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 420)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { viewModel.canAdvance = true }
    }
}
