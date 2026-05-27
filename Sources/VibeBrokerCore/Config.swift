import Foundation

public enum Effect: String, Codable, Sendable {
    case solid
    case breathe
    case blink
    case blinkThenSolid = "blink_then_solid"
}

public struct ColorConfig: Codable, Sendable, Equatable {
    public let rgb: [Int]            // [r, g, b], 0-255
    public let brightness: Int       // 0-255
    public let effect: Effect
}

public struct BrokerConfig: Codable, Sendable {
    public let port: UInt16
}

public struct HAConfig: Codable, Sendable {
    public let url: URL
    public let token: String
    public let lightEntity: String
}

public struct BehaviorConfig: Codable, Sendable {
    public let sessionTtlSeconds: TimeInterval
    public let errorAutoClearSeconds: TimeInterval
    public let doneBlinkSeconds: TimeInterval
    public let waitingInputBlinkSeconds: TimeInterval
    public let debounceMillis: Int
}

public struct Config: Sendable {
    public let broker: BrokerConfig
    public let homeAssistant: HAConfig
    public let behavior: BehaviorConfig
    public let colors: [State: ColorConfig]

    private struct Raw: Codable {
        let broker: BrokerConfig
        let homeAssistant: HAConfig
        let behavior: BehaviorConfig
        let colors: [String: ColorConfig]
    }

    public static func parse(_ data: Data) throws -> Config {
        let raw = try JSONDecoder().decode(Raw.self, from: data)

        var byState: [State: ColorConfig] = [:]
        for state in State.allCases {
            guard let color = raw.colors[state.serializedName] else {
                throw ParseError.missingColor(state.serializedName)
            }
            byState[state] = color
        }

        return Config(
            broker: raw.broker,
            homeAssistant: raw.homeAssistant,
            behavior: raw.behavior,
            colors: byState
        )
    }

    public enum ParseError: Error, Equatable {
        case missingColor(String)
    }

    public static func loadFromDisk(_ url: URL) throws -> Config {
        try parse(try Data(contentsOf: url))
    }
}
