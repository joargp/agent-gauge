import Foundation

struct UsageWindow: Equatable, Sendable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Date?

    var remainingPercent: Double {
        min(100, max(0, 100 - usedPercent))
    }

    var remainingFraction: Double {
        remainingPercent / 100
    }
}

struct CodexUsageSnapshot: Equatable, Sendable {
    static let fiveHourDurationMins = 300
    static let weeklyDurationMins = 10_080

    let primary: UsageWindow?
    let secondary: UsageWindow?
    let planType: String?
    let fetchedAt: Date

    var fiveHourWindow: UsageWindow? {
        window(withDuration: Self.fiveHourDurationMins) ?? primary
    }

    var weeklyWindow: UsageWindow? {
        window(withDuration: Self.weeklyDurationMins) ?? secondary
    }

    private func window(withDuration duration: Int) -> UsageWindow? {
        [primary, secondary]
            .compactMap { $0 }
            .first { $0.windowDurationMins == duration }
    }
}
