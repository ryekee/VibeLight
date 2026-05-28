import Foundation
import VibeBrokerCore

public final class ScenePackInstaller: @unchecked Sendable {
    public enum Error: Swift.Error {
        case http(Int)
        case transport(String)
        case encoding
    }

    private let baseURL: URL
    private let token: String
    private let session: URLSession

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    public func install(config: Config) async throws {
        let entity = config.homeAssistant.lightEntity
        for state in VibeBrokerCore.State.allCases {
            let color = config.colors[state]!
            let sceneId = "vibelight_\(state.serializedName)"
            let entityAttrs: [String: Any] = [
                "state": "on",
                "rgb_color": color.rgb,
                "brightness": color.brightness,
            ]
            let payload: [String: Any] = [
                "name": "VibeLight: \(state.serializedName)",
                "icon": "mdi:lightbulb",
                "entities": [entity: entityAttrs],
            ]
            try await postJSON(path: "/api/config/scene/config/\(sceneId)", body: payload)
        }
    }

    public func uninstall() async throws {
        for state in VibeBrokerCore.State.allCases {
            let sceneId = "vibelight_\(state.serializedName)"
            try await delete(path: "/api/config/scene/config/\(sceneId)")
        }
    }

    private func postJSON(path: String, body: [String: Any]) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 3.0
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch { throw Error.encoding }
        try await send(req)
    }

    private func delete(path: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 3.0
        try await send(req)
    }

    private func send(_ req: URLRequest) async throws {
        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw Error.http(-1) }
        if !(200..<300).contains(http.statusCode) { throw Error.http(http.statusCode) }
    }
}
