import SwiftUI

struct HomeAssistantTab: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View {
        Text("Home Assistant — Task 13").foregroundColor(.secondary).padding()
    }
}
