// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ClaudeGauge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ClaudeGauge", targets: ["ClaudeGauge"]),
        .executable(name: "claude-gauge-capture", targets: ["ClaudeGaugeCapture"])
    ],
    targets: [
        .target(
            name: "ClaudeGaugeCore",
            path: "Sources/ClaudeGaugeCore"
        ),
        .executableTarget(
            name: "ClaudeGauge",
            dependencies: ["ClaudeGaugeCore"],
            path: "Sources/ClaudeGauge"
        ),
        .executableTarget(
            name: "ClaudeGaugeCapture",
            dependencies: ["ClaudeGaugeCore"],
            path: "Sources/ClaudeGaugeCapture"
        ),
        .testTarget(
            name: "ClaudeGaugeTests",
            dependencies: ["ClaudeGauge", "ClaudeGaugeCore"],
            path: "Tests/ClaudeGaugeTests"
        )
    ]
)
