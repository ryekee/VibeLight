import Foundation

public enum State: String, CaseIterable, Sendable {
    case idle
    case done
    case working
    case compacting
    case waitingInput
    case needsAuth
    case error

    public var priority: Int {
        switch self {
        case .idle:         return 0
        case .done:         return 1
        case .working:      return 2
        case .compacting:   return 3
        case .waitingInput: return 4
        case .needsAuth:    return 5
        case .error:        return 6
        }
    }

    public var serializedName: String {
        switch self {
        case .idle:         return "idle"
        case .done:         return "done"
        case .working:      return "working"
        case .compacting:   return "compacting"
        case .waitingInput: return "waiting_input"
        case .needsAuth:    return "needs_auth"
        case .error:        return "error"
        }
    }
}
