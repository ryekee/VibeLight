import Foundation

public protocol LightServiceCaller: Sendable {
    func callService(domain: String, service: String, data: [String: Any]) async throws
}

public final class HAClient: @unchecked Sendable {
    public enum Error: Swift.Error, Equatable {
        case unauthorized
        case server(Int)
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

    public func callService(domain: String, service: String,
                            data: [String: Any]) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/services/\(domain)/\(service)"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 2.0
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: data)
        } catch {
            throw Error.encoding
        }

        let (_, response) = try await sendRequest(request)
        try assertOK(response)
    }

    /// Probes `GET /api/`. Returns normally on a 2xx response; throws
    /// `.unauthorized` on 401, `.server(code)` on other non-2xx, and
    /// `.transport` when the host is unreachable. Callers must not
    /// discard the result — a thrown error is the only failure signal.
    public func getApiStatus() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 0.5

        let (_, response) = try await sendRequest(request)
        try assertOK(response)
    }

    private func sendRequest(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: req)
        } catch {
            throw Error.transport(String(describing: error))
        }
    }

    private func assertOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw Error.server(-1)
        }
        if http.statusCode == 401 { throw Error.unauthorized }
        if !(200..<300).contains(http.statusCode) {
            throw Error.server(http.statusCode)
        }
    }
}

extension HAClient: LightServiceCaller {}
