import SwiftUI

struct SettingsWindow: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View {
        Text("Settings — implemented in Task 12").padding(40)
            .frame(width: 480, height: 320)
    }
}
