// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AgentGauge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AgentGauge", targets: ["AgentGauge"]),
        .executable(name: "claude-gauge-capture", targets: ["ClaudeGaugeCapture"])
    ],
    targets: [
        .target(
            name: "GaugeCore",
            path: "Sources/GaugeCore"
        ),
        .target(
            name: "ClaudeProvider",
            dependencies: ["GaugeCore"],
            path: "Sources/ClaudeProvider"
        ),
        .target(
            name: "CodexProvider",
            dependencies: ["GaugeCore"],
            path: "Sources/CodexProvider"
        ),
        .executableTarget(
            name: "AgentGauge",
            dependencies: ["GaugeCore", "ClaudeProvider", "CodexProvider"],
            path: "Sources/AgentGauge"
        ),
        .executableTarget(
            name: "ClaudeGaugeCapture",
            dependencies: ["ClaudeProvider"],
            path: "Sources/ClaudeGaugeCapture"
        ),
        .testTarget(
            name: "GaugeCoreTests",
            dependencies: ["GaugeCore"],
            path: "Tests/GaugeCoreTests"
        ),
        .testTarget(
            name: "ClaudeProviderTests",
            dependencies: ["ClaudeProvider", "GaugeCore"],
            path: "Tests/ClaudeProviderTests"
        ),
        .testTarget(
            name: "CodexProviderTests",
            dependencies: ["CodexProvider", "GaugeCore"],
            path: "Tests/CodexProviderTests"
        ),
        .testTarget(
            name: "AgentGaugeTests",
            dependencies: ["AgentGauge", "GaugeCore", "ClaudeProvider", "CodexProvider"],
            path: "Tests/AgentGaugeTests"
        )
    ]
)
