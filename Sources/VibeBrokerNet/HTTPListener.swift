import Foundation
import Network

public struct HTTPResponse: Sendable {
    public let status: Int
    public let body: Data
    public let contentType: String

    public init(status: Int, body: Data, contentType: String = "application/json") {
        self.status = status
        self.body = body
        self.contentType = contentType
    }
}

public actor HTTPListener {
    public typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    private let requestedPort: NWEndpoint.Port
    private let handler: Handler
    private var listener: NWListener?

    public init(port: UInt16, handler: @escaping Handler) {
        self.requestedPort = NWEndpoint.Port(rawValue: port) ?? .any
        self.handler = handler
    }

    public func start() async throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(using: params, on: requestedPort)
        listener.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            // Spec §8: only accept loopback connections.
            if !Self.isLoopback(conn.endpoint) {
                conn.cancel()
                return
            }
            Task { await self.handle(conn) }
        }
        // Assign before start so cancel() works even if we throw.
        self.listener = listener

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let box = ContinuationBox(cont)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    box.resume()
                case .failed(let e):
                    box.resumeThrowing(e)
                case .cancelled:
                    box.resumeThrowing(NSError(domain: "NWListener", code: 0,
                                               userInfo: [NSLocalizedDescriptionKey: "listener cancelled"]))
                default:
                    break
                }
            }
            listener.start(queue: .global())
        }
    }

    public func boundPort() -> UInt16 {
        listener?.port?.rawValue ?? 0
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handle(_ conn: NWConnection) async {
        conn.start(queue: .global())
        do {
            let raw = try await readUntilHeadersAndBody(conn)
            let request = try HTTPRequest.parse(raw)
            let response = await handler(request)
            try await send(response, on: conn)
        } catch {
            try? await send(HTTPResponse(status: 400, body: Data()), on: conn)
        }
        conn.cancel()
    }

    private func readUntilHeadersAndBody(_ conn: NWConnection) async throws -> Data {
        enum ReadError: Error { case prematureClose }
        var buffer = Data()
        while true {
            let chunk = try await receiveOnce(conn)
            buffer.append(chunk)
            let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8))
            if let end = headerEnd {
                let headerString = String(data: buffer.subdata(in: 0..<end.lowerBound), encoding: .utf8) ?? ""
                let contentLength = parseContentLength(headerString)
                let bodyReceived = buffer.count - end.upperBound
                if bodyReceived >= contentLength {
                    return buffer
                }
            }
            if chunk.isEmpty {
                // Client closed before full request arrived.
                throw ReadError.prematureClose
            }
        }
    }

    private func parseContentLength(_ headers: String) -> Int {
        for line in headers.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(value) ?? 0
            }
        }
        return 0
    }

    private func receiveOnce(_ conn: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                cont.resume(returning: data ?? Data())
            }
        }
    }

    private func send(_ response: HTTPResponse, on conn: NWConnection) async throws {
        let statusText = HTTPListener.statusText(response.status)
        var head = "HTTP/1.1 \(response.status) \(statusText)\r\n"
        head += "Content-Type: \(response.contentType)\r\n"
        head += "Content-Length: \(response.body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var full = Data(head.utf8)
        full.append(response.body)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: full, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            })
        }
    }

    private static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        if case let .hostPort(host, _) = endpoint {
            switch host {
            case .ipv4(let addr):
                return addr.isLoopback
            case .ipv6(let addr):
                return addr.isLoopback
            case .name(let name, _):
                return name == "localhost"
            @unknown default:
                return false
            }
        }
        return false
    }

    private static func statusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default:  return "OK"
        }
    }
}

// MARK: - ContinuationBox

/// Thread-safe wrapper that ensures a CheckedContinuation is resumed exactly once.
private final class ContinuationBox: @unchecked Sendable {
    private var cont: CheckedContinuation<Void, Error>?
    private let lock = NSLock()

    init(_ c: CheckedContinuation<Void, Error>) { cont = c }

    func resume() {
        lock.lock(); defer { lock.unlock() }
        cont?.resume()
        cont = nil
    }

    func resumeThrowing(_ e: Error) {
        lock.lock(); defer { lock.unlock() }
        cont?.resume(throwing: e)
        cont = nil
    }
}
