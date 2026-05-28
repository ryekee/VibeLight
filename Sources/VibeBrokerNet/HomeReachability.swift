import Foundation
import Network

public actor HomeReachability {
    public typealias Probe = @Sendable () async -> Bool

    private let probe: Probe
    private var currentValue: Bool = false
    private var continuations: [AsyncStream<Bool>.Continuation] = []
    private var pathMonitor: NWPathMonitor?
    private var periodicTask: Task<Void, Never>?

    public init(probe: @escaping Probe) {
        self.probe = probe
    }

    public func current() -> Bool { currentValue }

    @discardableResult
    public func checkNow() async -> Bool {
        let result = await probe()
        currentValue = result
        for cont in continuations {
            cont.yield(result)
        }
        return result
    }

    public func start() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { await self?.checkNow() }
        }
        monitor.start(queue: .global())
        self.pathMonitor = monitor

        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.checkNow()
            }
        }
    }

    public func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        periodicTask?.cancel()
        periodicTask = nil
        for cont in continuations { cont.finish() }
        continuations.removeAll()
    }

    public func stream() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            continuations.append(continuation)
        }
    }

    /// Convenience: build a probe that hits HA's `/api/` endpoint.
    public static func haProbe(baseURL: URL, token: String,
                                session: URLSession = .shared,
                                timeout: TimeInterval = 0.5) -> Probe {
        return { @Sendable in
            var req = URLRequest(url: baseURL.appendingPathComponent("api/"))
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = timeout
            do {
                let (_, resp) = try await session.data(for: req)
                guard let http = resp as? HTTPURLResponse else { return false }
                return (200..<300).contains(http.statusCode)
            } catch {
                return false
            }
        }
    }
}
