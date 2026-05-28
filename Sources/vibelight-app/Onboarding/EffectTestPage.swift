import SwiftUI

struct EffectTestPage: View {
    @ObservedObject var viewModel: OnboardingViewModel
    var body: some View {
        Text("Effect Test — implemented in Task 11").foregroundColor(.secondary)
    }
}
