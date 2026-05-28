import XCTest
@testable import VibeBrokerNet
@testable import VibeBrokerCore

final class ScenePackInstallerTests: XCTestCase {
    private func makeConfig() -> Config {
        BrokerEmulatedDriverSolidTests().makeConfigForBreathe()
    }

    private func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    func testInstallCreates7Scenes() async throws {
        let capturedPaths = CapturedPaths()
        MockURLProtocol.handler = { req in
            Task { await capturedPaths.append(req.url!.path) }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("{}".utf8))
        }
        let installer = ScenePackInstaller(
            baseURL: URL(string: "http://h:8123")!, token: "t",
            session: makeSession()
        )
        try await installer.install(config: makeConfig())

        let paths = await capturedPaths.snapshot()
        XCTAssertEqual(paths.count, 7)
        XCTAssertTrue(paths.contains { $0.contains("vibelight_idle") })
        XCTAssertTrue(paths.contains { $0.contains("vibelight_working") })
        XCTAssertTrue(paths.contains { $0.contains("vibelight_error") })
    }

    func testUninstallDeletes7Scenes() async throws {
        let deletePaths = CapturedPaths()
        MockURLProtocol.handler = { req in
            if req.httpMethod == "DELETE" {
                Task { await deletePaths.append(req.url!.path) }
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("{}".utf8))
        }
        let installer = ScenePackInstaller(
            baseURL: URL(string: "http://h:8123")!, token: "t",
            session: makeSession()
        )
        try await installer.uninstall()

        let paths = await deletePaths.snapshot()
        XCTAssertEqual(paths.count, 7)
    }

    func testInstallPropagatesAuthError() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (resp, Data("{}".utf8))
        }
        let installer = ScenePackInstaller(
            baseURL: URL(string: "http://h:8123")!, token: "t",
            session: makeSession()
        )
        do {
            try await installer.install(config: makeConfig())
            XCTFail("expected throw")
        } catch {
            // expected
        }
    }
}

actor CapturedPaths {
    private var paths: [String] = []
    func append(_ p: String) { paths.append(p) }
    func snapshot() -> [String] { paths }
}
