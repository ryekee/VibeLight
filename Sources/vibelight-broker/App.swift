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
        let host = BrokerHost(config: config)
        try await host.start()

        let actualPort = await host.boundPort()
        print("vibelight-broker: listening on 127.0.0.1:\(actualPort)")

        await waitForShutdownSignal()
        await host.stop()
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
