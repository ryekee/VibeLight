import Foundation

public enum HookName: String, Sendable {
    case sessionStart      = "SessionStart"
    case userPromptSubmit  = "UserPromptSubmit"
    case preToolUse        = "PreToolUse"
    case postToolUse       = "PostToolUse"
    case notification      = "Notification"
    case preCompact        = "PreCompact"
    case stop              = "Stop"
    case sessionEnd        = "SessionEnd"
}

public struct HookEvent: Sendable {
    public let hookName: HookName
    public let sessionId: String
    public let cwd: String?
    public let toolResponseIsError: Bool
    public let notificationMessage: String?

    public enum ParseError: Error {
        case unknownHook(String)
        case missingSessionId
        case invalidJSON
    }

    public static func parse(hookName rawName: String, body: Data) throws -> HookEvent {
        guard let hookName = HookName(rawValue: rawName) else {
            throw ParseError.unknownHook(rawName)
        }

        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                throw ParseError.invalidJSON
            }
            json = parsed
        } catch {
            throw ParseError.invalidJSON
        }

        guard let sessionId = json["session_id"] as? String, !sessionId.isEmpty else {
            throw ParseError.missingSessionId
        }

        let cwd = json["cwd"] as? String

        var isError = false
        if hookName == .postToolUse,
           let resp = json["tool_response"] as? [String: Any],
           let flag = resp["is_error"] as? Bool {
            isError = flag
        }

        var notifMsg: String? = nil
        if hookName == .notification {
            notifMsg = json["message"] as? String
        }

        return HookEvent(
            hookName: hookName,
            sessionId: sessionId,
            cwd: cwd,
            toolResponseIsError: isError,
            notificationMessage: notifMsg
        )
    }
}
