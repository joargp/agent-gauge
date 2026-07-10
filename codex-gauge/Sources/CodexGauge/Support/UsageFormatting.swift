import Foundation

enum UsageFormatting {
    static func wholePercent(_ value: Double) -> Int {
        Int(min(100, max(0, value)).rounded())
    }

    static func resetDescription(resetsAt: Date?, now: Date = Date()) -> String {
        guard let resetsAt else { return "Reset time unavailable" }
        let seconds = Int(resetsAt.timeIntervalSince(now))
        guard seconds > 0 else { return "Resetting now" }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 {
            return hours > 0 ? "Resets in \(days)d \(hours)h" : "Resets in \(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "Resets in \(hours)h \(minutes)m" : "Resets in \(hours)h"
        }
        return "Resets in \(max(1, minutes))m"
    }

    static func lastUpdatedDescription(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Not updated yet" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "Updated just now" }
        if seconds < 3_600 { return "Updated \(seconds / 60)m ago" }
        return "Updated \(seconds / 3_600)h ago"
    }

    static func planDisplayName(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}
