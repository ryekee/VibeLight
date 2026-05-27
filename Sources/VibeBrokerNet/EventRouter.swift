import Foundation
import VibeBrokerCore

public actor EventRouter {
    private let store: SessionStore
    private let driver: LightDriver
    private let config: Config

    private var errorClearTasks: [String: Task<Void, Never>] = [:]
    private var debounceTask: Task<Void, Never>?

    public init(store: SessionStore, driver: LightDriver, config: Config) {
        self.store = store
        self.driver = driver
        self.config = config
    }

    public func handle(_ request: HTTPRequest) async -> HTTPResponse {
        switch (request.method, request.path) {
        case ("POST", "/event"):
            return await handleEvent(request)
        case ("GET", "/state"):
            return await handleState()
        case ("POST", "/test"):
            return await handleTest(request)
        case ("POST", "/reload"):
            return HTTPResponse(status: 204, body: Data())
        case ("GET", "/health"):
            return HTTPResponse(status: 200, body: Data("{\"ok\":true}".utf8))
        default:
            return HTTPResponse(status: 404, body: Data())
        }
    }

    private func handleEvent(_ request: HTTPRequest) async -> HTTPResponse {
        guard let hookName = request.query["hook"] else {
            return HTTPResponse(status: 400, body: Data("missing hook".utf8))
        }
        do {
            let event = try HookEvent.parse(hookName: hookName, body: request.body)
            await store.handle(event)

            errorClearTasks[event.sessionId]?.cancel()
            errorClearTasks.removeValue(forKey: event.sessionId)

            await renderEffective()

            let snapshot = await store.snapshot()
            if let record = snapshot[event.sessionId], record.state == .error {
                scheduleErrorClear(sessionId: event.sessionId)
            }

            return HTTPResponse(status: 204, body: Data())
        } catch {
            return HTTPResponse(status: 400, body: Data("\(error)".utf8))
        }
    }

    private func scheduleErrorClear(sessionId: String) {
        let nanos = UInt64(config.behavior.errorAutoClearSeconds * 1_000_000_000)
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            await self.clearErrorIfStillError(sessionId: sessionId)
        }
        errorClearTasks[sessionId] = task
    }

    private func clearErrorIfStillError(sessionId: String) async {
        let snapshot = await store.snapshot()
        guard snapshot[sessionId]?.state == .error else { return }
        await store.setState(.idle, for: sessionId)
        errorClearTasks.removeValue(forKey: sessionId)
        await renderEffective()
    }

    private func renderEffective() async {
        debounceTask?.cancel()
        let ms = config.behavior.debounceMillis
        if ms == 0 {
            await actuallyRender()
        } else {
            debounceTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.actuallyRender()
            }
        }
    }

    private func actuallyRender() async {
        let snapshot = await store.snapshot()
        let effective = Arbiter.compute(snapshot)
        await driver.render(effective)
    }

    private func handleState() async -> HTTPResponse {
        let snapshot = await store.snapshot()
        let effective = Arbiter.compute(snapshot)
        let body: [String: Any] = [
            "effective": effective.serializedName,
            "sessions": snapshot.mapValues { rec -> [String: Any] in
                ["state": rec.state.serializedName,
                 "since": rec.since.timeIntervalSince1970,
                 "cwd": rec.cwd as Any]
            },
        ]
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
        return HTTPResponse(status: 200, body: data)
    }

    private func handleTest(_ request: HTTPRequest) async -> HTTPResponse {
        guard let stateName = request.query["state"],
              let state = State.allCases.first(where: { $0.serializedName == stateName }) else {
            return HTTPResponse(status: 400, body: Data("invalid state".utf8))
        }
        await driver.render(state)
        return HTTPResponse(status: 204, body: Data())
    }
}
