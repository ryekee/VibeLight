import SwiftUI
import VibeBrokerCore
import VibeBrokerNet

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var effectiveState: VibeBrokerCore.State = .idle
    @Published private(set) var sessions: [SessionRecord] = []
    @Published private(set) var paused: Bool = false
    @Published private(set) var listening: Bool = false
    @Published private(set) var lastError: String?

    private var host: BrokerHost?
    private var refreshTask: Task<Void, Never>?

    init() { bootstrap() }

    func bootstrap() {
        guard host == nil else { return }
        Task {
            do {
                let configPath = Self.defaultConfigPath()
                guard FileManager.default.fileExists(atPath: configPath.path) else {
                    self.lastError = "config not found at \(configPath.path)"
                    return
                }
                let config = try Config.loadFromDisk(configPath)
                let host = BrokerHost(config: config)
                await host.setObserver { [weak self] state in
                    await self?.updateEffective(state)
                }
                try await host.start()
                self.host = host
                self.listening = true
                self.startSessionRefresh()
            } catch {
                self.lastError = String(describing: error)
            }
        }
    }

    func shutdown() async {
        refreshTask?.cancel()
        refreshTask = nil
        await host?.stop()
        host = nil
        listening = false
    }

    func setPaused(_ paused: Bool) {
        Task {
            await host?.setPaused(paused)
            self.paused = paused
        }
    }

    func testRender(_ state: VibeBrokerCore.State) {
        Task { await host?.testRender(state) }
    }

    private func updateEffective(_ state: VibeBrokerCore.State) {
        Task { @MainActor in
            self.effectiveState = state
        }
    }

    private func startSessionRefresh() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let snapshot = await self.host?.sessionSnapshot() {
                    let sorted = snapshot.values.sorted { $0.since > $1.since }
                    await MainActor.run { self.sessions = sorted }
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private static func defaultConfigPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/vibelight/config.json")
    }
}
