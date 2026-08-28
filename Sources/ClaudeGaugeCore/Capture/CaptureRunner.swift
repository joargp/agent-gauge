import Foundation

enum CaptureRunnerError: Error, Equatable {
    /// The statusline payload wasn't valid JSON.
    case invalidInput
}

public struct CaptureOutcome: Equatable, Sendable {
    /// Cache bytes to write, or nil when nothing should be written.
    public let cacheData: Data?
    public let statusLineText: String
}

/// Pure statusline-capture logic shared by the capture binary and tests.
///
/// - Cache writes are change-detected: an unchanged payload (including the
///   rounded capture timestamp) is skipped to avoid disk churn while a
///   session idles at constant usage.
/// - Early-session renders without `rate_limits` never clobber good cached
///   data; the status line text is still produced.
public enum CaptureRunner {
    /// Capture timestamps are rounded so an idle session rewrites the cache
    /// at most six times per minute.
    static let capturedAtRounding: TimeInterval = 10

    public static func run(
        input: Data,
        existingCache: Data?,
        now: Date = Date()
    ) throws -> CaptureOutcome {
        let capture: StatuslineCaptureDecoder.Capture
        do {
            capture = try StatuslineCaptureDecoder.decode(input)
        } catch {
            throw CaptureRunnerError.invalidInput
        }

        let statusLineText = Self.statusLineText(for: capture, now: now)

        guard capture.hadRateLimits else {
            return CaptureOutcome(cacheData: nil, statusLineText: statusLineText)
        }

        // Claude Code drops an individual window once its resets_at passes.
        // Preserve the last-known window until a replacement arrives so the
        // app can recognize that rollover and hide the stale percentage.
        let previousPayload = existingCache.flatMap {
            try? UsageCacheDecoder.decodePayload($0)
        }
        let roundedAt = (
            now.timeIntervalSince1970 / capturedAtRounding
        ).rounded(.down) * capturedAtRounding

        let payload = UsageCachePayload(
            fiveHour: mergedWindow(
                incoming: capture.fiveHour.map(CacheWindow.init),
                previous: previousPayload?.fiveHour
            ),
            sevenDay: mergedWindow(
                incoming: capture.sevenDay.map(CacheWindow.init),
                previous: previousPayload?.sevenDay
            ),
            capturedAt: max(roundedAt, previousPayload?.capturedAt ?? roundedAt),
            claudeCodeVersion: capture.claudeCodeVersion ?? previousPayload?.claudeCodeVersion
        )

        let encoded = try encode(payload)
        if let existingCache, existingCache == encoded {
            return CaptureOutcome(cacheData: nil, statusLineText: statusLineText)
        }
        return CaptureOutcome(cacheData: encoded, statusLineText: statusLineText)
    }

    static func encode(_ payload: UsageCachePayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    static func statusLineText(
        for capture: StatuslineCaptureDecoder.Capture,
        now: Date = Date()
    ) -> String {
        var segments: [String] = []

        if let name = capture.modelDisplayName, !name.isEmpty {
            segments.append(name)
        }
        if let fiveHour = capture.fiveHour, !fiveHour.isRolledOver(now: now) {
            segments.append(usageSegment(label: "5h", window: fiveHour))
        }
        if let sevenDay = capture.sevenDay, !sevenDay.isRolledOver(now: now) {
            segments.append(usageSegment(label: "W", window: sevenDay))
        }

        return segments.joined(separator: " · ")
    }

    private static func usageSegment(label: String, window: UsageWindow) -> String {
        let remaining = Int(min(100, max(0, 100 - window.usedPercent)).rounded())
        let text = "\(label) \(remaining)%"
        if remaining <= 10 {
            return "\u{1B}[31m\(text)\u{1B}[0m"
        }
        if remaining <= 25 {
            return "\u{1B}[33m\(text)\u{1B}[0m"
        }
        return text
    }

    /// Reconciles concurrent sessions without allowing an older session to
    /// regress a newer cache entry. Reset times advance between windows; usage
    /// is monotonic within a window that has the same reset time.
    private static func mergedWindow(
        incoming: CacheWindow?,
        previous: CacheWindow?
    ) -> CacheWindow? {
        guard let incoming else { return previous }
        guard let previous else { return incoming }

        switch (incoming.resetsAt, previous.resetsAt) {
        case let (incomingReset?, previousReset?):
            if incomingReset > previousReset { return incoming }
            if incomingReset < previousReset { return previous }
        case (.some, .none):
            return incoming
        case (.none, .some):
            return previous
        case (.none, .none):
            break
        }

        return incoming.usedPercentage >= previous.usedPercentage
            ? incoming
            : previous
    }
}
