import Foundation
import VibeBrokerCore

public actor ScenePackDriver: LightDriver {
    private let client: LightServiceCaller
    private var currentTask: Task<Void, Never>?

    public init(client: LightServiceCaller) {
        self.client = client
    }

    public func render(_ state: VibeBrokerCore.State) async {
        await cancel()
        let entityId = "scene.vibelight_\(state.serializedName)"
        currentTask = Task { [client] in
            try? await client.callService(
                domain: "scene", service: "turn_on",
                data: ["entity_id": entityId]
            )
        }
    }

    public func cancel() async {
        currentTask?.cancel()
        currentTask = nil
    }
}
