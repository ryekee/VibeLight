import SwiftUI

struct GeneralPage: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View {
        Text("General — Task 3").foregroundColor(.secondary)
    }
}
