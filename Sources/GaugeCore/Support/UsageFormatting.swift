import Foundation

public enum UsageFormatting {
    public static func wholePercent(_ value: Double) -> Int {
        Int(min(100, max(0, value)).rounded())
    }

    public static func resetDescription(resetsAt: Date?, now: Date = Date()) -> String {
        guard let resetsAt else { return "Reset time unavailable" }
        let interval = resetsAt.timeIntervalSince(now)
        guard interval.isFinite else { return "Reset time unavailable" }
        guard interval > 0 else { return "Resetting now" }
        let seconds = Int(min(1_000_000_000, interval.rounded(.down)))

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

    public static func resetDateDescription(resetsAt: Date?, now: Date = Date()) -> String? {
        guard let resetsAt else { return nil }
        let timestamp = resetsAt.timeIntervalSince1970
        guard timestamp.isFinite, timestamp > 0, timestamp <= 10_000_000_000 else {
            return nil
        }

        var format = Date.FormatStyle.dateTime
            .month(.abbreviated)
            .day()
            .hour()
            .minute()

        if !Calendar.autoupdatingCurrent.isDate(resetsAt, equalTo: now, toGranularity: .year) {
            format = format.year()
        }

        return resetsAt.formatted(format)
    }

    public static func lastUpdatedDescription(_ date: Date?, now: Date = Date()) -> String {
        ageDescription(date, now: now, prefix: "Updated", unavailable: "Update time unavailable")
    }

    public static func lastCaptureDescription(_ date: Date?, now: Date = Date()) -> String {
        ageDescription(date, now: now, prefix: "Last capture", unavailable: "Capture time unavailable")
    }

    private static func ageDescription(
        _ date: Date?,
        now: Date,
        prefix: String,
        unavailable: String
    ) -> String {
        guard let date else { return "Not captured yet" }
        let interval = now.timeIntervalSince(date)
        guard interval.isFinite else { return unavailable }
        let seconds = Int(min(1_000_000_000, max(0, interval).rounded(.down)))
        if seconds < 60 { return "\(prefix) just now" }
        if seconds < 3_600 { return "\(prefix) \(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(prefix) \(seconds / 3_600)h ago" }
        return "\(prefix) \(seconds / 86_400)d ago"
    }
}
