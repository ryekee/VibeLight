import Foundation
import VibeBrokerCore

public actor BrokerEmulatedDriver: LightDriver {
    private let client: LightServiceCaller
    private let config: Config
    private var currentTask: Task<Void, Never>?

    public init(client: LightServiceCaller, config: Config) {
        self.client = client
        self.config = config
    }

    public func render(_ state: State) async {
        await cancel()
        let color = config.colors[state]!  // config schema guarantees presence
        let entityId = config.homeAssistant.lightEntity

        switch color.effect {
        case .solid:
            currentTask = Task { [client] in
                try? await client.callService(
                    domain: "light", service: "turn_on",
                    data: LightPayload.turnOn(entityId: entityId, color: color, transition: 0.3)
                )
            }
        case .breathe:
            currentTask = Task { [client, color, entityId] in
                var high = true
                let highBrightness = color.brightness
                let lowBrightness = max(20, color.brightness / 3)
                while !Task.isCancelled {
                    try? await client.callService(
                        domain: "light", service: "turn_on",
                        data: LightPayload.turnOn(
                            entityId: entityId, color: color, transition: 1.0,
                            brightnessOverride: high ? highBrightness : lowBrightness
                        )
                    )
                    high.toggle()
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 s
                }
            }
        case .blink, .blinkThenSolid:
            // Implemented in task 12.
            break
        }
    }

    public func cancel() async {
        currentTask?.cancel()
        currentTask = nil
    }
}
