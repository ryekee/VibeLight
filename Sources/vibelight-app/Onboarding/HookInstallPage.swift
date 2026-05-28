import SwiftUI

struct HookInstallPage: View {
    @ObservedObject var viewModel: OnboardingViewModel
    var body: some View {
        Text("Hook Install — implemented in Task 10").foregroundColor(.secondary)
    }
}
