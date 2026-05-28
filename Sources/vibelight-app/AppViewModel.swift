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
    @Published private(set) var isAtHome: Bool = false
    @Published var needsOnboarding: Bool = false

    let settings = SettingsStore()
    let hookInstaller = HookInstaller()

    private var host: BrokerHost?
    private var reachability: HomeReachability?
    private var refreshTask: Task<Void, Never>?
    private var pauseResumeTask: Task<Void, Never>?
    private var reachabilityTask: Task<Void, Never>?

    init() {
        settings.onChange = { [weak self] in
            Task { @MainActor [weak self] in await self?.handleSettingsChange() }
        }
        if settings.isConfigured {
            bootstrap()
        } else {
            needsOnboarding = true
        }
    }

    func bootstrap() {
        guard host == nil else { return }
        Task {
            do {
                let config = try ConfigBuilder.build(from: settings)
                try ConfigBuilder.writeConfigJSON(settings)

                let host = BrokerHost(config: config)
                await host.setObserver { [weak self] state in
                    await self?.updateEffective(state)
                }
                await host.setDriverMode(.init(rawValue: settings.renderMode.rawValue) ?? .brokerEmulated)
                try await host.start()
                self.host = host
                self.listening = true
                self.startSessionRefresh()
                self.startReachability(url: config.homeAssistant.url, token: config.homeAssistant.token)
            } catch {
                self.lastError = String(describing: error)
            }
        }
    }

    func shutdown() async {
        refreshTask?.cancel()
        reachabilityTask?.cancel()
        await reachability?.stop()
        await host?.stop()
        host = nil
        listening = false
    }

    private func handleSettingsChange() async {
        guard settings.isConfigured else { return }
        do {
            try ConfigBuilder.writeConfigJSON(settings)
            if let host {
                let cfg = try ConfigBuilder.build(from: settings)
                await host.reload(config: cfg)
                await host.setDriverMode(.init(rawValue: settings.renderMode.rawValue) ?? .brokerEmulated)
            } else {
                bootstrap()
            }
        } catch {
            lastError = String(describing: error)
        }
    }

    private func startReachability(url: URL, token: String) {
        let probe = HomeReachability.haProbe(baseURL: url, token: token)
        let reach = HomeReachability(probe: probe)
        Task { await reach.start() }
        self.reachability = reach
        reachabilityTask = Task { [weak self] in
            guard let reach = self?.reachability else { return }
            let stream = await reach.stream()
            for await value in stream {
                await MainActor.run { self?.isAtHome = value }
            }
        }
        Task { _ = await reach.checkNow() }
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

    func finishOnboarding() {
        needsOnboarding = false
        if host == nil { bootstrap() }
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
}
