import XCTest
@testable import VibeBrokerCore

final class ConfigBuilderTests: XCTestCase {
    // These tests cover the JSON-round-trip path for ConfigBuilder. The full
    // SettingsStore is @MainActor and tied to UserDefaults — we only test the
    // pure data flow here. UI integration is verified manually.

    func testConfigParsesAfterRoundTrip() throws {
        let cfg = Config(
            broker: BrokerConfig(port: 17345),
            homeAssistant: HAConfig(url: URL(string: "http://h:8123")!, token: "tk", lightEntity: "light.x"),
            behavior: BehaviorConfig(
                sessionTtlSeconds: 300, errorAutoClearSeconds: 5,
                doneBlinkSeconds: 2, waitingInputBlinkSeconds: 3, debounceMillis: 100
            ),
            colors: [
                .idle:         ColorConfig(rgb: [80, 30, 120],  brightness: 80,  effect: .solid),
                .working:      ColorConfig(rgb: [40, 120, 255], brightness: 200, effect: .breathe),
                .compacting:   ColorConfig(rgb: [240, 220, 60], brightness: 200, effect: .breathe),
                .waitingInput: ColorConfig(rgb: [255, 140, 30], brightness: 220, effect: .blinkThenSolid),
                .needsAuth:    ColorConfig(rgb: [255, 30, 30],  brightness: 230, effect: .solid),
                .error:        ColorConfig(rgb: [255, 30, 30],  brightness: 230, effect: .blink),
                .done:         ColorConfig(rgb: [80, 30, 120],  brightness: 200, effect: .blink),
            ]
        )

        // Manually replicate the JSON shape writeConfigJSON produces:
        var raw: [String: Any] = [
            "broker": ["port": Int(cfg.broker.port)],
            "homeAssistant": [
                "url": cfg.homeAssistant.url.absoluteString,
                "token": cfg.homeAssistant.token,
                "lightEntity": cfg.homeAssistant.lightEntity,
            ],
            "behavior": [
                "sessionTtlSeconds":        cfg.behavior.sessionTtlSeconds,
                "errorAutoClearSeconds":    cfg.behavior.errorAutoClearSeconds,
                "doneBlinkSeconds":         cfg.behavior.doneBlinkSeconds,
                "waitingInputBlinkSeconds": cfg.behavior.waitingInputBlinkSeconds,
                "debounceMillis":           cfg.behavior.debounceMillis,
            ],
        ]
        var colors: [String: Any] = [:]
        for (state, c) in cfg.colors {
            colors[state.serializedName] = [
                "rgb": c.rgb, "brightness": c.brightness, "effect": c.effect.rawValue,
            ]
        }
        raw["colors"] = colors

        let data = try JSONSerialization.data(withJSONObject: raw)
        let parsed = try Config.parse(data)

        XCTAssertEqual(parsed.broker.port, cfg.broker.port)
        XCTAssertEqual(parsed.homeAssistant.url, cfg.homeAssistant.url)
        XCTAssertEqual(parsed.homeAssistant.token, cfg.homeAssistant.token)
        XCTAssertEqual(parsed.colors[.working]?.rgb, [40, 120, 255])
    }
}
