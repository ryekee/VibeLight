import SwiftUI

struct AboutPage: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.yellow)
                VStack(alignment: .leading) {
                    Text("VibeLight").font(.title).bold()
                    Text("Version \(version)").foregroundColor(.secondary)
                }
            }

            SettingsBox {
                SettingsRow("Source", description: "VibeLight is open source.") {
                    Button("View on GitHub") {
                        // Repo URL is filled in once the project is pushed; for now this is a placeholder.
                        // P5 will populate from Bundle.main.infoDictionary if the homepage URL is set.
                    }
                    .disabled(true)
                }
                Divider().padding(.horizontal, 12)
                SettingsRow("License", description: "MIT.") {
                    EmptyView()
                }
            }

            Text("Built with Swift, SwiftUI, and Network.framework. Zero third-party dependencies.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
    }
}
