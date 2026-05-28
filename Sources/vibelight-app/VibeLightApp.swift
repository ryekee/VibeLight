import SwiftUI

@main
struct VibeLightApp: App {
    var body: some Scene {
        MenuBarExtra("VibeLight", systemImage: "circle.fill") {
            Text("VibeLight (scaffold)")
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
