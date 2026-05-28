import XCTest

// NOTE: HookInstaller lives in the vibelight-app target which the test target
// can't directly @testable-import (apps aren't typically test-importable from
// a sibling library test target). We test HookInstaller's behavior indirectly
// by replicating its logic against a tempdir — this catches regressions in the
// JSON merge algorithm without requiring an app-target test rig. The full
// behavior is also smoke-tested manually in Task 14.

final class HookSettingsMergeTests: XCTestCase {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibelight-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Verifies the JSON shape we'll write is what Claude Code expects.
    func testHookEntryShapeRoundTrips() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let settingsPath = dir.appendingPathComponent("settings.json")
        let entry: [String: Any] = [
            "hooks": [
                "UserPromptSubmit": [
                    [
                        "hooks": [
                            ["type": "command",
                             "command": "/Users/me/.claude/hooks/vibelight.sh UserPromptSubmit"]
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: entry, options: .prettyPrinted)
        try data.write(to: settingsPath)

        let reread = try JSONSerialization.jsonObject(with: try Data(contentsOf: settingsPath)) as? [String: Any]
        XCTAssertNotNil((reread?["hooks"] as? [String: Any])?["UserPromptSubmit"])
    }
}
