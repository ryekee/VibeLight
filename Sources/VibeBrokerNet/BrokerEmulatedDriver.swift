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
        case .breathe, .blink, .blinkThenSolid:
            // Implemented in tasks 11, 12.
            break
        }
    }

    public func cancel() async {
        currentTask?.cancel()
        currentTask = nil
    }
}
