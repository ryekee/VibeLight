import Foundation
import VibeBrokerCore

public enum DriverMode: String, Sendable, Equatable {
    case brokerEmulated
    case scenePack
}

public actor BrokerHost {
    private var config: Config
    private let store: SessionStore
    private let haClient: HAClient
    private var driver: any LightDriver
    private var mode: DriverMode = .brokerEmulated
    private let router: EventRouter
    private let listener: HTTPListener

    private var pruneTask: Task<Void, Never>?

    public init(config: Config) {
        self.config = config
        self.store = SessionStore(ttlSeconds: config.behavior.sessionTtlSeconds)
        self.haClient = HAClient(
            baseURL: config.homeAssistant.url,
            token: config.homeAssistant.token
        )
        let initial = BrokerEmulatedDriver(client: haClient, config: config)
        self.driver = initial
        self.router = EventRouter(store: store, driver: initial, config: config)
        let router = self.router
        self.listener = HTTPListener(port: config.broker.port) { request in
            await router.handle(request)
        }
    }

    public func start() async throws {
        try await listener.start()
        let store = self.store
        pruneTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                _ = await store.pruneExpired()
            }
        }
    }

    public func stop() async {
        pruneTask?.cancel()
        pruneTask = nil
        await listener.stop()
        await driver.cancel()
    }

    public func boundPort() async -> UInt16 {
        await listener.boundPort()
    }

    public func setObserver(_ observer: @escaping EventRouter.EffectiveStateObserver) async {
        await router.setObserver(observer)
    }

    public func setPaused(_ paused: Bool) async {
        await router.setPaused(paused)
    }

    public func isPaused() async -> Bool {
        await router.isPaused()
    }

    public func sessionSnapshot() async -> [String: SessionRecord] {
        await store.snapshot()
    }

    /// Trigger a one-off driver render (used by Test light effect menu).
    public func testRender(_ state: VibeBrokerCore.State) async {
        await driver.render(state)
    }

    public func discoverHistoricalSessions(
        root: URL = TranscriptDiscovery.defaultClaudeRoot(),
        cutoff: Date = Date().addingTimeInterval(-24 * 3600),
        limit: Int = 40
    ) async -> Int {
        let discovery = TranscriptDiscovery()
        let ids: [String]
        do {
            ids = try await discovery.findRecentSessionIDs(root: root, cutoff: cutoff, limit: limit)
        } catch {
            return 0
        }
        for id in ids {
            let event = HookEvent(
                hookName: .sessionStart,
                sessionId: id,
                cwd: nil,
                toolResponseIsError: false,
                notificationMessage: nil
            )
            await store.handle(event)
        }
        return ids.count
    }

    public func driverMode() -> DriverMode { mode }

    public func setDriverMode(_ newMode: DriverMode) async {
        guard newMode != mode else { return }
        await driver.cancel()
        mode = newMode
        switch newMode {
        case .brokerEmulated:
            driver = BrokerEmulatedDriver(client: haClient, config: config)
        case .scenePack:
            driver = ScenePackDriver(client: haClient)
        }
        await router.setDriver(driver)
    }

    public func reload(config newConfig: Config) async {
        config = newConfig
        await driver.cancel()
        switch mode {
        case .brokerEmulated:
            driver = BrokerEmulatedDriver(client: haClient, config: newConfig)
        case .scenePack:
            driver = ScenePackDriver(client: haClient)
        }
        await router.setDriver(driver)
        await router.setConfig(newConfig)
    }
}
