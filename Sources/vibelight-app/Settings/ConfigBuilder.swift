import Foundation
import VibeBrokerCore

enum ConfigBuilder {
    enum BuildError: Error {
        case missingHAURL
        case invalidHAURL(String)
        case missingLightEntity
        case missingToken
    }

    @MainActor
    static func build(from settings: SettingsStore) throws -> Config {
        guard !settings.haURL.isEmpty else { throw BuildError.missingHAURL }
        guard let url = URL(string: settings.haURL) else {
            throw BuildError.invalidHAURL(settings.haURL)
        }
        guard !settings.haLightEntity.isEmpty else { throw BuildError.missingLightEntity }
        guard let token = settings.haToken, !token.isEmpty else { throw BuildError.missingToken }

        return Config(
            broker: BrokerConfig(port: UInt16(settings.brokerPort)),
            homeAssistant: HAConfig(url: url, token: token, lightEntity: settings.haLightEntity),
            behavior: BehaviorConfig(
                sessionTtlSeconds: 300,
                errorAutoClearSeconds: 5,
                doneBlinkSeconds: 2,
                waitingInputBlinkSeconds: 3,
                debounceMillis: 100
            ),
            colors: settings.colors
        )
    }

    /// Write the same settings out to `~/.config/vibelight/config.json` so the
    /// `vibelight-broker` CLI keeps working with the same values.
    @MainActor
    static func writeConfigJSON(_ settings: SettingsStore) throws {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/vibelight/config.json")
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var raw: [String: Any] = [:]
        raw["broker"] = ["port": settings.brokerPort]
        raw["homeAssistant"] = [
            "url": settings.haURL,
            "token": settings.haToken ?? "",
            "lightEntity": settings.haLightEntity,
        ]
        raw["behavior"] = [
            "sessionTtlSeconds":         300,
            "errorAutoClearSeconds":     5,
            "doneBlinkSeconds":          2,
            "waitingInputBlinkSeconds":  3,
            "debounceMillis":            100,
        ]
        var colorsOut: [String: Any] = [:]
        for (state, c) in settings.colors {
            colorsOut[state.serializedName] = [
                "rgb": c.rgb, "brightness": c.brightness,
                "effect": c.effect.rawValue,
            ]
        }
        raw["colors"] = colorsOut

        let data = try JSONSerialization.data(withJSONObject: raw, options: .prettyPrinted)
        try data.write(to: path, options: .atomic)
    }
}
