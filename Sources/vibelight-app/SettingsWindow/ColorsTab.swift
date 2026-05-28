import SwiftUI

struct ColorsTab: View {
    @ObservedObject var viewModel: AppViewModel
    var body: some View {
        Text("Colors & Effects — Task 14").foregroundColor(.secondary).padding()
    }
}
