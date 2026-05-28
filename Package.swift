// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VibeLight",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "VibeBrokerCore", targets: ["VibeBrokerCore"]),
        .library(name: "VibeBrokerNet", targets: ["VibeBrokerNet"]),
        .executable(name: "vibelight-broker", targets: ["vibelight-broker"]),
        .executable(name: "vibelight-app", targets: ["vibelight-app"]),
    ],
    targets: [
        .target(name: "VibeBrokerCore"),
        .target(name: "VibeBrokerNet", dependencies: ["VibeBrokerCore"]),
        .executableTarget(
            name: "vibelight-broker",
            dependencies: ["VibeBrokerCore", "VibeBrokerNet"]
        ),
        .executableTarget(
            name: "vibelight-app",
            dependencies: ["VibeBrokerCore", "VibeBrokerNet"],
            resources: [.copy("AppInfo.plist")]
        ),
        .testTarget(name: "VibeBrokerCoreTests", dependencies: ["VibeBrokerCore"]),
        .testTarget(
            name: "VibeBrokerNetTests",
            dependencies: ["VibeBrokerNet", "VibeBrokerCore"]
        ),
    ]
)
