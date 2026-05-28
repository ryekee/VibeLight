import Foundation
import VibeBrokerCore

public actor BrokerHost {
    private let config: Config
    private let store: SessionStore
    private let haClient: HAClient
    private let driver: BrokerEmulatedDriver
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
        self.driver = BrokerEmulatedDriver(client: haClient, config: config)
        self.router = EventRouter(store: store, driver: driver, config: config)
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
    public func testRender(_ state: State) async {
        await driver.render(state)
    }
}
