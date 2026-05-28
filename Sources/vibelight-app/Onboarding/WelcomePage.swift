import SwiftUI

struct WelcomePage: View {
    @ObservedObject var viewModel: OnboardingViewModel
    var body: some View {
        Text("Welcome — implemented in Task 9").foregroundColor(.secondary)
    }
}
