import Foundation

public struct UsageWindow: Equatable, Sendable {
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(usedPercent: Double, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Double {
        min(100, max(0, 100 - usedPercent))
    }

    public var remainingFraction: Double {
        remainingPercent / 100
    }

    /// True once the captured `resets_at` has passed, meaning the value no
    /// longer reflects the active window until a new capture arrives.
    public func isRolledOver(now: Date = Date()) -> Bool {
        guard let resetsAt else { return false }
        return resetsAt <= now
    }
}

/// How current the last statusline capture is.
public enum DataFreshness: Equatable, Sendable {
    case live
    case recent
    case stale

    public static let liveThreshold: TimeInterval = 120
    public static let recentThreshold: TimeInterval = 3_600

    public init(capturedAt: Date, now: Date) {
        let age = max(0, now.timeIntervalSince(capturedAt))
        if age <= Self.liveThreshold {
            self = .live
        } else if age <= Self.recentThreshold {
            self = .recent
        } else {
            self = .stale
        }
    }
}

/// What a usage ring should display for one window.
public enum WindowDisplayState: Equatable, Sendable {
    /// Fresh window data.
    case present(UsageWindow)
    /// The last captured `resets_at` passed while idle; usage is unknown
    /// until the next statusline capture.
    case rolledOver
    /// No data captured for this window yet.
    case awaitingCapture
}

public struct ClaudeUsageSnapshot: Equatable, Sendable {
    public let fiveHourWindow: UsageWindow?
    public let sevenDayWindow: UsageWindow?
    public let claudeCodeVersion: String?
    public let capturedAt: Date

    public init(
        fiveHourWindow: UsageWindow?,
        sevenDayWindow: UsageWindow?,
        claudeCodeVersion: String?,
        capturedAt: Date
    ) {
        self.fiveHourWindow = fiveHourWindow
        self.sevenDayWindow = sevenDayWindow
        self.claudeCodeVersion = claudeCodeVersion
        self.capturedAt = capturedAt
    }

    public func freshness(now: Date = Date()) -> DataFreshness {
        DataFreshness(capturedAt: capturedAt, now: now)
    }

    public func fiveHourState(now: Date = Date()) -> WindowDisplayState {
        displayState(for: fiveHourWindow, now: now)
    }

    public func sevenDayState(now: Date = Date()) -> WindowDisplayState {
        displayState(for: sevenDayWindow, now: now)
    }

    private func displayState(for window: UsageWindow?, now: Date) -> WindowDisplayState {
        guard let window else { return .awaitingCapture }
        if window.isRolledOver(now: now) {
            return .rolledOver
        }
        return .present(window)
    }
}
