import SwiftUI

struct GeneralTab: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(
                get: { viewModel.settings.launchAtLogin },
                set: { viewModel.settings.launchAtLogin = $0 }
            ))
            Toggle("Notify on HA errors", isOn: Binding(
                get: { viewModel.settings.notifyOnHAError },
                set: { viewModel.settings.notifyOnHAError = $0 }
            ))
        }
        .padding()
    }
}
