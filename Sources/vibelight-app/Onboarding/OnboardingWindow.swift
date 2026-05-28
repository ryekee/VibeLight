import SwiftUI

struct OnboardingWindow: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(viewModel.step.title).font(.title2).bold()
            stepIndicator
        }
        .padding()
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingViewModel.Step.allCases, id: \.rawValue) { s in
                Circle()
                    .fill(s.rawValue <= viewModel.step.rawValue ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.step {
        case .welcome:         WelcomePage(viewModel: viewModel)
        case .haConnection:    HAConnectionPage(viewModel: viewModel)
        case .lightSelection:  LightSelectionPage(viewModel: viewModel)
        case .networkConfirm:  NetworkConfirmPage(viewModel: viewModel)
        case .hookInstall:     HookInstallPage(viewModel: viewModel)
        case .effectTest:      EffectTestPage(viewModel: viewModel)
        case .done:            OnboardingDonePage(viewModel: viewModel)
        }
    }

    private var footer: some View {
        HStack {
            if viewModel.step != .welcome && viewModel.step != .done {
                Button("Back") { viewModel.previous() }
            }
            Spacer()
            if viewModel.step == .done {
                Button("Done") { viewModel.finish() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Next") { viewModel.next() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canAdvance)
            }
        }
        .padding()
    }
}
