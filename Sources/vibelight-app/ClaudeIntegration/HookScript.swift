import Foundation

enum HookScript {
    /// Verbatim contents of the hook shell script. Increment scriptVersion when
    /// the script content changes; HookInstaller compares to detect "out of date".
    static let scriptVersion = "1"

    static let body: String = """
    #!/usr/bin/env bash
    # vibelight: forward Claude Code hook payload to local broker.
    # vibelight-script-version: \(scriptVersion)
    exec curl -s -m 0.2 -X POST \\
      -H 'Content-Type: application/json' \\
      --data-binary @- \\
      "http://127.0.0.1:17345/event?hook=$1" >/dev/null 2>&1 || true
    """

    static let hookEvents: [String] = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "Notification", "PreCompact", "Stop", "SessionEnd",
    ]
}
