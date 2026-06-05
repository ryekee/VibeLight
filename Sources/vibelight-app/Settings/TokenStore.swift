import Foundation

/// File-backed store for the Home Assistant token.
///
/// The token lives at `~/.config/vibelight/ha_token` (mode 0600), next to the
/// `config.json` the broker already reads — so all VibeLight state sits under
/// one app directory instead of the system Keychain. Tokens written before this
/// change are migrated out of the Keychain on first read.
enum TokenStore {
    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/vibelight/ha_token")
    }

    static func get() -> String? {
        if let onDisk = readFile() { return onDisk }
        // One-time migration: lift any token still in the old Keychain location
        // into the file, then drop the Keychain item so it isn't left behind.
        if let legacy = KeychainHelper.get("haToken"), !legacy.isEmpty {
            set(legacy)
            KeychainHelper.delete(for: "haToken")
            return legacy
        }
        return nil
    }

    static func set(_ value: String?) {
        let url = fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let value, !value.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            try value.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.path
            )
        } catch {
            // Best-effort: a write failure leaves the prior value in place.
        }
    }

    private static func readFile() -> String? {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
