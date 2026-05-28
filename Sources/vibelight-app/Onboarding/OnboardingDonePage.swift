import SwiftUI

struct OnboardingDonePage: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            Text("All set!").font(.title).bold()
            Text("VibeLight will now reflect your Claude Code agent's state on your light. Find more options under Settings… in the menubar.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 420)
            Text("Want even smoother effects? Try Settings → Home Assistant → Scene pack mode.")
                .font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { viewModel.canAdvance = true }
    }
}
