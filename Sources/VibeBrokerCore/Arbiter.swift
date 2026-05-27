import Foundation

public enum Arbiter {
    public static func compute(_ sessions: [String: SessionRecord]) -> State {
        guard !sessions.isEmpty else { return .idle }
        let sorted = sessions.values.sorted { a, b in
            if a.state.priority != b.state.priority {
                return a.state.priority > b.state.priority
            }
            return a.since > b.since
        }
        return sorted.first?.state ?? .idle
    }
}
