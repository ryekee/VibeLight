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
    @Published private(set) var pauseUntil: Date?

    private var host: BrokerHost?
    private var refreshTask: Task<Void, Never>?
    private var pauseResumeTask: Task<Void, Never>?

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

    func pauseFor(_ duration: PauseDuration) {
        let resumeAt = duration.resumeDate(now: Date())
        pauseUntil = resumeAt
        setPausedInternal(true)
        pauseResumeTask?.cancel()
        pauseResumeTask = Task { [weak self] in
            let nanos = UInt64(max(0, resumeAt.timeIntervalSinceNow) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.resume() }
        }
    }

    func resume() {
        pauseResumeTask?.cancel()
        pauseResumeTask = nil
        pauseUntil = nil
        setPausedInternal(false)
    }

    private func setPausedInternal(_ paused: Bool) {
        Task {
            await host?.setPaused(paused)
            await MainActor.run { self.paused = paused }
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
