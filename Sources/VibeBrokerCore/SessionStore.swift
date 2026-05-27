import Foundation

public struct SessionRecord: Sendable, Equatable {
    public let id: String
    public var state: State
    public var since: Date
    public var lastEventAt: Date
    public var cwd: String?
}

public actor SessionStore {
    private var sessions: [String: SessionRecord] = [:]
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date

    public init(ttlSeconds: TimeInterval, now: @escaping @Sendable () -> Date = { Date() }) {
        self.ttl = ttlSeconds
        self.now = now
    }

    public func handle(_ event: HookEvent) {
        let timestamp = now()

        if event.hookName == .sessionEnd {
            sessions.removeValue(forKey: event.sessionId)
            return
        }

        if var existing = sessions[event.sessionId] {
            let next = Transition.apply(from: existing.state, event: event)
            if next != existing.state {
                existing.state = next
                existing.since = timestamp
            }
            existing.lastEventAt = timestamp
            if let cwd = event.cwd { existing.cwd = cwd }
            sessions[event.sessionId] = existing
        } else {
            let initialState = Transition.apply(from: .idle, event: event)
            sessions[event.sessionId] = SessionRecord(
                id: event.sessionId, state: initialState,
                since: timestamp, lastEventAt: timestamp, cwd: event.cwd
            )
        }
    }

    @discardableResult
    public func pruneExpired() -> Int {
        let cutoff = now().addingTimeInterval(-ttl)
        let expired = sessions.filter { $0.value.lastEventAt < cutoff }.map(\.key)
        for id in expired { sessions.removeValue(forKey: id) }
        return expired.count
    }

    public func snapshot() -> [String: SessionRecord] {
        sessions
    }

    /// For internal callers needing to override state without an event (used by error auto-clear timer).
    public func setState(_ state: State, for sessionId: String) {
        guard var existing = sessions[sessionId] else { return }
        existing.state = state
        existing.since = now()
        existing.lastEventAt = now()
        sessions[sessionId] = existing
    }
}
