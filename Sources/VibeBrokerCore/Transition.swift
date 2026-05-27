import Foundation

public enum Transition {
    public static func apply(from state: State, event: HookEvent) -> State {
        switch event.hookName {
        case .sessionStart:
            return .idle

        case .userPromptSubmit, .preToolUse:
            return .working

        case .postToolUse:
            return event.toolResponseIsError ? .error : .working

        case .notification:
            guard let msg = event.notificationMessage?.lowercased() else {
                return .needsAuth
            }
            if msg.contains("permission") || msg.contains("approve") {
                return .needsAuth
            }
            return .waitingInput

        case .preCompact:
            return .compacting

        case .stop:
            return .done

        case .sessionEnd:
            return .idle
        }
    }
}
