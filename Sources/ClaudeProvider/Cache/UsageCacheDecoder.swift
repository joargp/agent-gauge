import Foundation
import GaugeCore

public enum UsageCacheDecoder {
    private static let maximumTimestamp: TimeInterval = 10_000_000_000

    public static func decode(_ data: Data) throws -> UsageSnapshot {
        try decodeCached(data).snapshot
    }

    static func decodeCached(_ data: Data) throws -> (snapshot: UsageSnapshot, configDir: String?) {
        let payload = try decodeWirePayload(data)
        let snapshot = UsageSnapshot(
            fiveHourWindow: try payload.fiveHour.map(window),
            weeklyWindow: try payload.sevenDay.map(window),
            badge: payload.claudeCodeVersion.map { "Claude Code \($0)" },
            capturedAt: Date(timeIntervalSince1970: payload.capturedAt),
            fiveHourCapturedAt: payload.fiveHour?.capturedAt.map(Date.init(timeIntervalSince1970:)),
            weeklyCapturedAt: payload.sevenDay?.capturedAt.map(Date.init(timeIntervalSince1970:))
        )
        return (snapshot, payload.configDir)
    }

    /// The helper needs validated wire data to merge concurrent captures.
    static func decodePayload(_ data: Data) throws -> UsageCachePayload {
        let payload = try decodeWirePayload(data)
        _ = try payload.fiveHour.map(window)
        _ = try payload.sevenDay.map(window)
        return payload
    }

    private static func decodeWirePayload(_ data: Data) throws -> UsageCachePayload {
        let payload: UsageCachePayload
        do {
            payload = try JSONDecoder().decode(UsageCachePayload.self, from: data)
        } catch {
            throw ClaudeUsageError.invalidCache
        }

        guard validTimestamp(payload.capturedAt) else {
            throw ClaudeUsageError.invalidCache
        }
        return payload
    }

    private static func window(_ cached: CacheWindow) throws -> UsageWindow {
        guard cached.usedPercentage.isFinite,
              cached.resetsAt.map(validTimestamp) ?? true,
              cached.capturedAt.map(validTimestamp) ?? true
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
