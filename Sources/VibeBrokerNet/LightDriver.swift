import Foundation
import VibeBrokerCore

public protocol LightDriver: Sendable {
    /// Render the effective state on the light. Cancels any in-flight effect.
    func render(_ state: State) async
    /// Cancel any in-flight effect loop without changing the light.
    func cancel() async
}

public enum LightPayload {
    /// Build a `light.turn_on` service data payload from a color config.
    /// `transition` is in seconds (HA semantics: server interpolates over this duration).
    public static func turnOn(entityId: String, color: ColorConfig,
                              transition: Double, brightnessOverride: Int? = nil) -> [String: Any] {
        [
            "entity_id": entityId,
            "rgb_color": color.rgb,
            "brightness": brightnessOverride ?? color.brightness,
            "transition": transition,
        ]
    }

    public static func turnOff(entityId: String, transition: Double = 0) -> [String: Any] {
        [
            "entity_id": entityId,
            "transition": transition,
        ]
    }
}
