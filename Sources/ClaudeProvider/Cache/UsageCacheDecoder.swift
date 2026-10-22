import Foundation
import GaugeCore

public enum UsageCacheDecoder {
    private static let maximumTimestamp: TimeInterval = 10_000_000_000

    public static func decode(_ data: Data) throws -> UsageSnapshot {
        let payload = try decodePayload(data)

        return UsageSnapshot(
            fiveHourWindow: try payload.fiveHour.map(window),
            weeklyWindow: try payload.sevenDay.map(window),
            badge: payload.claudeCodeVersion.map { "Claude Code \($0)" },
            capturedAt: Date(timeIntervalSince1970: payload.capturedAt)
        )
    }

    /// Decodes and validates the persisted wire payload before it can be used
    /// either by the app or as prior state during concurrent-capture merging.
    static func decodePayload(_ data: Data) throws -> UsageCachePayload {
        let payload: UsageCachePayload
        do {
            payload = try JSONDecoder().decode(UsageCachePayload.self, from: data)
        } catch {
            throw ClaudeUsageError.invalidCache
        }

        guard validTimestamp(payload.capturedAt) else {
            throw ClaudeUsageError.invalidCache
        }
        _ = try payload.fiveHour.map(window)
        _ = try payload.sevenDay.map(window)

        return payload
    }

    private static func window(_ cached: CacheWindow) throws -> UsageWindow {
        guard cached.usedPercentage.isFinite,
              cached.resetsAt.map(validTimestamp) ?? true
        else {
            throw ClaudeUsageError.invalidCache
        }
        return UsageWindow(
            usedPercent: cached.usedPercentage,
            resetsAt: cached.resetsAt.map { Date(timeIntervalSince1970: $0) }
        )
    }

    private static func validTimestamp(_ value: TimeInterval) -> Bool {
        value.isFinite && value > 0 && value <= maximumTimestamp
    }
}
