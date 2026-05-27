import XCTest
@testable import VibeBrokerCore

final class ConfigTests: XCTestCase {
    private let validJSON = #"""
    {
      "broker": { "port": 17345 },
      "homeAssistant": {
        "url": "http://homeassistant.local:8123",
        "token": "abc123",
        "lightEntity": "light.desk_strip"
      },
      "behavior": {
        "sessionTtlSeconds": 300,
        "errorAutoClearSeconds": 5,
        "doneBlinkSeconds": 2,
        "waitingInputBlinkSeconds": 3,
        "debounceMillis": 100
      },
      "colors": {
        "idle":         { "rgb": [80, 30, 120], "brightness": 80,  "effect": "solid" },
        "working":      { "rgb": [40, 120, 255], "brightness": 200, "effect": "breathe" },
        "compacting":   { "rgb": [240, 220, 60], "brightness": 200, "effect": "breathe" },
        "waiting_input":{ "rgb": [255, 140, 30], "brightness": 220, "effect": "blink_then_solid" },
        "needs_auth":   { "rgb": [255, 30, 30], "brightness": 230, "effect": "solid" },
        "error":        { "rgb": [255, 30, 30], "brightness": 230, "effect": "blink" },
        "done":         { "rgb": [80, 30, 120], "brightness": 200, "effect": "blink" }
      }
    }
    """#

    func testParseValid() throws {
        let cfg = try Config.parse(Data(validJSON.utf8))

        XCTAssertEqual(cfg.broker.port, 17345)
        XCTAssertEqual(cfg.homeAssistant.url.absoluteString, "http://homeassistant.local:8123")
        XCTAssertEqual(cfg.homeAssistant.token, "abc123")
        XCTAssertEqual(cfg.homeAssistant.lightEntity, "light.desk_strip")
        XCTAssertEqual(cfg.behavior.sessionTtlSeconds, 300)
        XCTAssertEqual(cfg.colors[.working]?.rgb, [40, 120, 255])
        XCTAssertEqual(cfg.colors[.working]?.effect, .breathe)
    }

    func testMissingRequiredFieldThrows() {
        let badJSON = #"{"broker":{"port":17345}}"#
        XCTAssertThrowsError(try Config.parse(Data(badJSON.utf8)))
    }

    func testEffectParsing() throws {
        let cfg = try Config.parse(Data(validJSON.utf8))
        XCTAssertEqual(cfg.colors[.error]?.effect, .blink)
        XCTAssertEqual(cfg.colors[.waitingInput]?.effect, .blinkThenSolid)
        XCTAssertEqual(cfg.colors[.idle]?.effect, .solid)
    }
}
