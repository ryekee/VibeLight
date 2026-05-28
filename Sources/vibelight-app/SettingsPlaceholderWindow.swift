import SwiftUI

struct SettingsPlaceholderWindow: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gear")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Settings UI coming in P3").font(.headline)
            Text("For now, edit ~/.config/vibelight/config.json directly.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(40)
        .frame(width: 360, height: 200)
    }
}
