import Foundation

enum HookInstallStatus {
    case notInstalled
    case installed
}

enum HookInstallerError: Error {
    case writeFailed(String)
}

struct HookInstaller {
    /// Root for Claude Code config. Override in tests to point at a temp dir.
    let claudeRoot: URL

    init(claudeRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")) {
        self.claudeRoot = claudeRoot
    }

    var hookScriptPath: URL {
        claudeRoot.appendingPathComponent("hooks/vibelight.sh")
    }

    var settingsPath: URL {
        claudeRoot.appendingPathComponent("settings.json")
    }

    func status() -> HookInstallStatus {
        FileManager.default.fileExists(atPath: hookScriptPath.path)
            ? .installed : .notInstalled
    }

    /// The `vibelight-script-version` marker in the installed script, or nil if
    /// the script isn't installed (or predates the marker entirely).
    func installedScriptVersion() -> String? {
        guard let contents = try? String(contentsOf: hookScriptPath, encoding: .utf8) else {
            return nil
        }
        let marker = "vibelight-script-version:"
        for line in contents.split(separator: "\n") {
            if let range = line.range(of: marker) {
                return line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Rewrite the installed script when it predates `HookScript.scriptVersion`.
    /// Only touches an already-installed script — never installs fresh, so we
    /// don't opt users in behind their back. `install()` is idempotent, so the
    /// settings.json hook entries are left as-is. Returns true if it upgraded.
    @discardableResult
    func upgradeIfOutdated() -> Bool {
        guard status() == .installed else { return false }
        guard installedScriptVersion() != HookScript.scriptVersion else { return false }
        try? install()
        return true
    }

    func install() throws {
        try FileManager.default.createDirectory(
            at: hookScriptPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try HookScript.body.write(to: hookScriptPath, atomically: true, encoding: .utf8)
        } catch {
            throw HookInstallerError.writeFailed("hook script: \(error)")
        }
        do {
            var attrs = try FileManager.default.attributesOfItem(atPath: hookScriptPath.path)
            attrs[.posixPermissions] = 0o755
            try FileManager.default.setAttributes(attrs, ofItemAtPath: hookScriptPath.path)
        } catch {
            throw HookInstallerError.writeFailed("chmod: \(error)")
        }

        // Patch settings.json: append vibelight entries to each hook event, skipping
        // any event that already has a vibelight.sh hook.
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = json
        }
        var hooks: [String: Any] = root["hooks"] as? [String: Any] ?? [:]

        for event in HookScript.hookEvents {
            var groups: [[String: Any]] = hooks[event] as? [[String: Any]] ?? []
            let alreadyHasVibelight = groups.contains(where: { group in
                let entries = group["hooks"] as? [[String: Any]] ?? []
                return entries.contains(where: { e in
                    (e["command"] as? String)?.contains("vibelight.sh") == true
                })
            })
            if alreadyHasVibelight { continue }
            let newGroup: [String: Any] = [
                "hooks": [
                    ["type": "command",
                     "command": "\(hookScriptPath.path) \(event)"]
                ]
            ]
            groups.append(newGroup)
            hooks[event] = groups
        }
        root["hooks"] = hooks

        do {
            let data = try JSONSerialization.data(
                withJSONObject: root, options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: settingsPath, options: .atomic)
        } catch {
            throw HookInstallerError.writeFailed("settings.json: \(error)")
        }
    }

    func uninstall() throws {
        // Remove vibelight entries from settings.json
        if let data = try? Data(contentsOf: settingsPath),
           var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var hooks: [String: Any] = root["hooks"] as? [String: Any] ?? [:]
            for event in HookScript.hookEvents {
                guard var groups = hooks[event] as? [[String: Any]] else { continue }
                groups.removeAll { group in
                    let entries = group["hooks"] as? [[String: Any]] ?? []
                    return entries.contains(where: { e in
                        (e["command"] as? String)?.contains("vibelight.sh") == true
                    })
                }
                if groups.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = groups
                }
            }
            if hooks.isEmpty {
                root.removeValue(forKey: "hooks")
            } else {
                root["hooks"] = hooks
            }
            let data2 = try JSONSerialization.data(
                withJSONObject: root, options: [.prettyPrinted, .sortedKeys]
            )
            try data2.write(to: settingsPath, options: .atomic)
        }
        try? FileManager.default.removeItem(at: hookScriptPath)
    }
}
