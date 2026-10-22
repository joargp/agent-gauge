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

/// How current the last usage reading is.
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
    /// The last known `resets_at` passed without a newer reading; usage is
    /// unknown until the provider reports again.
    case rolledOver
    /// No data read for this window yet.
    case awaitingCapture
    /// The provider reported usage, but the plan has no such window.
    case noLimit
}

public struct UsageSnapshot: Equatable, Sendable {
    public let fiveHourWindow: UsageWindow?
    public let weeklyWindow: UsageWindow?
    /// Short provider detail for the popover header, such as a CLI version
    /// or subscription plan.
    public let badge: String?
    public let capturedAt: Date
    /// True when the provider reports every window the plan has, so an absent
    /// window means no such limit rather than a reading still to come.
    public let absentWindowsHaveNoLimit: Bool

    public init(
        fiveHourWindow: UsageWindow?,
        weeklyWindow: UsageWindow?,
        badge: String?,
        capturedAt: Date,
        absentWindowsHaveNoLimit: Bool = false
    ) {
        self.fiveHourWindow = fiveHourWindow
        self.weeklyWindow = weeklyWindow
        self.badge = badge
        self.capturedAt = capturedAt
        self.absentWindowsHaveNoLimit = absentWindowsHaveNoLimit
    }

    public func freshness(now: Date = Date()) -> DataFreshness {
        DataFreshness(capturedAt: capturedAt, now: now)
    }

    public func fiveHourState(now: Date = Date()) -> WindowDisplayState {
        displayState(for: fiveHourWindow, now: now)
    }

    public func weeklyState(now: Date = Date()) -> WindowDisplayState {
        displayState(for: weeklyWindow, now: now)
    }

    private func displayState(for window: UsageWindow?, now: Date) -> WindowDisplayState {
        guard let window else {
            return absentWindowsHaveNoLimit ? .noLimit : .awaitingCapture
        }
        if window.isRolledOver(now: now) {
            return .rolledOver
        }
        return .present(window)
    }
}
