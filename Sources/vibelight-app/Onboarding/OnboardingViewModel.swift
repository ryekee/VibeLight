import SwiftUI
import VibeBrokerCore
import VibeBrokerNet

@MainActor
final class OnboardingViewModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome
        case haConnection
        case lightSelection
        case networkConfirm
        case hookInstall
        case effectTest
        case done

        var title: String {
            switch self {
            case .welcome:         return "Welcome"
            case .haConnection:    return "Connect to Home Assistant"
            case .lightSelection:  return "Choose a light"
            case .networkConfirm:  return "Confirm home network"
            case .hookInstall:     return "Install Claude Code hooks"
            case .effectTest:      return "Test light effects"
            case .done:            return "All set"
            }
        }
    }

    @Published var step: Step = .welcome
    @Published var canAdvance: Bool = true
    @Published var lastError: String?

    let appViewModel: AppViewModel
    let settings: SettingsStore
    let discovery = HADiscovery()
    @Published var discovered: [DiscoveredHA] = []
    @Published var lightEntities: [String] = []

    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
        self.settings = appViewModel.settings
    }

    func next() {
        guard let nextStep = Step(rawValue: step.rawValue + 1) else { return }
        step = nextStep
    }

    func previous() {
        guard let prevStep = Step(rawValue: step.rawValue - 1) else { return }
        step = prevStep
    }

    func startDiscovery() {
        Task {
            await discovery.start()
            let stream = await discovery.stream()
            for await list in stream {
                await MainActor.run { self.discovered = list }
            }
        }
    }

    func stopDiscovery() {
        Task { await discovery.stop() }
    }

    func testHAConnection() async {
        guard !settings.haURL.isEmpty, let url = URL(string: settings.haURL),
              let token = settings.haToken, !token.isEmpty else {
            lastError = "URL and token required"
            return
        }
        let client = HAClient(baseURL: url, token: token)
        do {
            _ = try await client.getApiStatus()
            lastError = nil
        } catch {
            lastError = "Connection failed: \(error)"
        }
    }

    func fetchLightEntities() async {
        guard !settings.haURL.isEmpty, let url = URL(string: settings.haURL),
              let token = settings.haToken, !token.isEmpty else { return }
        var req = URLRequest(url: url.appendingPathComponent("api/states"))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 3.0
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                let lights = arr.compactMap { $0["entity_id"] as? String }
                    .filter { $0.hasPrefix("light.") }
                await MainActor.run { self.lightEntities = lights.sorted() }
            }
        } catch {
            await MainActor.run { self.lastError = "Failed to list lights: \(error)" }
        }
    }

    func finish() {
        appViewModel.finishOnboarding()
    }
}
