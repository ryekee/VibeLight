import Foundation
import Network

public struct DiscoveredHA: Sendable, Equatable, Identifiable {
    public let id: String   // unique name string
    public let name: String
    public let endpoint: String   // host:port suitable for URL building
}

public actor HADiscovery {
    private var browser: NWBrowser?
    private var continuations: [AsyncStream<[DiscoveredHA]>.Continuation] = []
    private var discovered: [String: DiscoveredHA] = [:]

    public init() {}

    public func start() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = false
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_home-assistant._tcp.", domain: "local.")
        let browser = NWBrowser(for: descriptor, using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { await self?.handle(results) }
        }
        browser.start(queue: .global())
        self.browser = browser
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        for cont in continuations { cont.finish() }
        continuations.removeAll()
        discovered.removeAll()
    }

    public func stream() -> AsyncStream<[DiscoveredHA]> {
        AsyncStream { continuation in
            continuation.yield(Array(discovered.values))
            continuations.append(continuation)
        }
    }

    public func current() -> [DiscoveredHA] {
        Array(discovered.values)
    }

    private func handle(_ results: Set<NWBrowser.Result>) {
        var newDict: [String: DiscoveredHA] = [:]
        for result in results {
            if case let .service(name, _, _, _) = result.endpoint {
                let endpointStr = "\(name).local."
                let item = DiscoveredHA(id: name, name: name, endpoint: endpointStr)
                newDict[name] = item
            }
        }
        discovered = newDict
        let list = Array(newDict.values)
        for cont in continuations {
            cont.yield(list)
        }
    }
}
