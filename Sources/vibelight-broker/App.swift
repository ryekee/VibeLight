import Foundation
import VibeBrokerCore
import VibeBrokerNet

@main
struct App {
    static func main() async throws {
        let configPath = parseConfigArg() ?? defaultConfigPath()
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            FileHandle.standardError.write(Data("config not found at \(configPath.path)\n".utf8))
            exit(2)
        }
        let config = try Config.loadFromDisk(configPath)
        let store = SessionStore(ttlSeconds: config.behavior.sessionTtlSeconds)
        let haClient = HAClient(
            baseURL: config.homeAssistant.url,
            token: config.homeAssistant.token
        )
        let driver = BrokerEmulatedDriver(client: haClient, config: config)
        let router = EventRouter(store: store, driver: driver, config: config)
        let listener = HTTPListener(port: config.broker.port) { request in
            await router.handle(request)
        }
        try await listener.start()

        let actualPort = await listener.boundPort()
        print("vibelight-broker: listening on 127.0.0.1:\(actualPort)")

        // Periodic TTL pruning every 60 s.
        let pruneTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                _ = await store.pruneExpired()
            }
        }
        defer { pruneTask.cancel() }

        await waitForShutdownSignal()
        await listener.stop()
        print("vibelight-broker: stopped")
    }

    private static func parseConfigArg() -> URL? {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--config"), idx + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[idx + 1])
    }

    private static func defaultConfigPath() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/vibelight/config.json")
    }

    private static func waitForShutdownSignal() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
            let source2 = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
            signal(SIGINT, SIG_IGN)
            signal(SIGTERM, SIG_IGN)
            let handler = {
                source.cancel()
                source2.cancel()
                cont.resume()
            }
            source.setEventHandler(handler: handler)
            source2.setEventHandler(handler: handler)
            source.resume()
            source2.resume()
        }
    }
}
