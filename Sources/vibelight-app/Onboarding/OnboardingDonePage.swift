import SwiftUI

struct OnboardingDonePage: View {
    @ObservedObject var viewModel: OnboardingViewModel
    var body: some View {
        Text("Done — implemented in Task 11").foregroundColor(.secondary)
    }
}
