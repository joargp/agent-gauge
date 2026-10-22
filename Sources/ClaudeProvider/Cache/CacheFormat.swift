import Foundation
import GaugeCore

/// On-disk locations for Agent Gauge's capture binary and usage cache.
public struct CacheLocations: Sendable {
    public let homeDirectory: URL

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.homeDirectory = homeDirectory
    }

    /// Directory that holds the capture binary and the usage cache.
    public var installDirectory: URL {
        homeDirectory.appendingPathComponent(".claude/claude-gauge", isDirectory: true)
    }

    /// The capture binary Claude Code's statusline invokes.
    public var captureExecutable: URL {
        installDirectory.appendingPathComponent("capture", isDirectory: false)
    }

    /// Cache file written by the capture binary and read by the app.
    public var cacheFile: URL {
        installDirectory.appendingPathComponent("last-usage.json", isDirectory: false)
    }

    /// Claude Code user settings that own the `statusLine` entry.
    public var claudeSettingsFile: URL {
        homeDirectory.appendingPathComponent(".claude/settings.json", isDirectory: false)
    }
}

/// Cache payload: what the capture binary writes and the app reads.
struct UsageCachePayload: Codable, Equatable, Sendable {
    var fiveHour: CacheWindow?
    var sevenDay: CacheWindow?
    /// Epoch seconds when the statusline capture ran (rounded by the writer).
    var capturedAt: TimeInterval
    var claudeCodeVersion: String?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case capturedAt = "captured_at"
        case claudeCodeVersion = "claude_code_version"
    }
}

struct CacheWindow: Codable, Equatable, Sendable {
    var usedPercentage: Double
    var resetsAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }

    init(usedPercentage: Double, resetsAt: TimeInterval?) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }

    init(_ window: UsageWindow) {
        self.init(
            usedPercentage: window.usedPercent,
            resetsAt: window.resetsAt?.timeIntervalSince1970
        )
    }
}
