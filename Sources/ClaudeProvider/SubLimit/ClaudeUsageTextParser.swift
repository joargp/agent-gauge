import Foundation
import GaugeCore

/// Parses the text `claude -p "/usage" --output-format json` returns.
public enum ClaudeUsageTextParser {
    /// The `result` text from the CLI's JSON output, or nil when the output
    /// isn't that JSON.
    public static func resultText(fromJSON data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? String
        else { return nil }
        return result
    }

    /// Only the subscription-wide weekly window, never a model-specific cap.
    static func parseWeekly(_ text: String, now: Date) -> UsageWindow? {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            guard let row = parseRow(String(rawLine)), row.name.lowercased() == "all models",
                  (0...100).contains(row.used),
                  let reset = row.reset.flatMap(resetFields),
                  let resetsAt = weeklyReset(reset, now: now)
            else { continue }
            return UsageWindow(usedPercent: row.used, resetsAt: resetsAt)
        }
        return nil
    }

    /// The Fable weekly window from the `/usage` text, or nil when the text
    /// has no such line (a plan without a Fable cap, or API-key output).
    public static func parseFable(_ text: String, now: Date = Date()) -> SubLimit? {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            guard let row = parseRow(String(rawLine)), row.name.lowercased().hasPrefix("fable"),
                  row.used.isFinite
            else { continue }

            let resetsAt = row.reset.flatMap(resetFields).flatMap { fableReset($0, now: now) }
            return SubLimit(
                name: row.name,
                window: UsageWindow(usedPercent: min(100, max(0, row.used)), resetsAt: resetsAt)
            )
        }
        return nil
    }

    private static func parseRow(_ line: String) -> (name: String, used: Double, reset: String?)? {
        guard let match = lineExpression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let name = capture(1, in: match, of: line),
              let used = capture(2, in: match, of: line).flatMap(Double.init)
        else { return nil }
        return (name, used, capture(3, in: match, of: line))
    }

    private struct ResetFields {
        var components: DateComponents
        let zoneIdentifier: String?
    }

    private static func resetFields(_ text: String) -> ResetFields? {
        guard let match = resetExpression.firstMatch(
            in: text, range: NSRange(text.startIndex..., in: text)
        ),
              let monthName = capture(1, in: match, of: text),
              let month = months[String(monthName.prefix(3)).lowercased()],
              let day = capture(2, in: match, of: text).flatMap(Int.init),
              var hour = capture(4, in: match, of: text).flatMap(Int.init),
              let meridiem = capture(6, in: match, of: text)?.lowercased(),
              (1...12).contains(hour)
        else { return nil }

        let minute = capture(5, in: match, of: text).flatMap(Int.init) ?? 0
        guard (0..<60).contains(minute) else { return nil }
        if hour == 12 { hour = 0 }
        if meridiem == "pm" { hour += 12 }

        return ResetFields(
            components: DateComponents(
                year: capture(3, in: match, of: text).flatMap(Int.init),
                month: month, day: day, hour: hour, minute: minute
            ),
            zoneIdentifier: capture(7, in: match, of: text)
        )
    }

    /// Verification requires a unique future reset within the weekly window.
    private static func weeklyReset(_ reset: ResetFields, now: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        if let identifier = reset.zoneIdentifier {
            guard let zone = TimeZone(identifier: identifier) else { return nil }
            calendar.timeZone = zone
        }
        let currentYear = calendar.component(.year, from: now)
        let latestReset = now.addingTimeInterval(7 * 24 * 60 * 60)
        // Try next year independently for yearless January resets.
        for year in reset.components.year.map({ [$0] }) ?? [currentYear, currentYear + 1] {
            var requested = reset.components
            requested.year = year
            requested.second = 0
            guard let date = calendar.date(from: requested),
                  date > now, date <= latestReset,
                  calendar.date(date, matchesComponents: requested),
                  !isRepeatedLocalTime(date, in: calendar.timeZone)
            else { continue }
            return date
        }
        return nil
    }

    /// Fable's display retains the original, lenient date inference.
    private static func fableReset(_ reset: ResetFields, now: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        if let zone = reset.zoneIdentifier.flatMap(TimeZone.init(identifier:)) {
            calendar.timeZone = zone
        }
        func date(year: Int) -> Date? {
            var requested = reset.components
            requested.year = year
            guard let date = calendar.date(from: requested),
                  calendar.component(.month, from: date) == requested.month,
                  calendar.component(.day, from: date) == requested.day
            else { return nil }
            return date
        }

        if let explicitYear = reset.components.year { return date(year: explicitYear) }
        let currentYear = calendar.component(.year, from: now)
        guard let thisYear = date(year: currentYear) else { return nil }
        // A date more than a day in the past means the next year's.
        if thisYear < now.addingTimeInterval(-86_400) {
            return date(year: currentYear + 1) ?? thisYear
        }
        return thisYear
    }

    private static func isRepeatedLocalTime(_ date: Date, in zone: TimeZone) -> Bool {
        let offset = zone.secondsFromGMT(for: date)
        // The same wall time satisfies date + offset == other + otherOffset.
        // Two days on each side cover even changes at the date line.
        let radius: TimeInterval = 2 * 24 * 60 * 60
        var probe = date.addingTimeInterval(-radius)
        let end = date.addingTimeInterval(radius)
        while true {
            let otherOffset = zone.secondsFromGMT(for: probe)
            if otherOffset != offset {
                let other = date.addingTimeInterval(TimeInterval(offset - otherOffset))
                if zone.secondsFromGMT(for: other) == otherOffset { return true }
            }
            guard let transition = zone.nextDaylightSavingTimeTransition(after: probe), transition <= end
            else { return false }
            probe = transition
        }
    }

    private static func capture(_ index: Int, in match: NSTextCheckingResult, of text: String) -> String? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }

    private static let months: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12
    ]

    // "Current week (Fable): 73% used · resets Nov 12 at 8pm (Europe/Oslo)"
    private static let lineExpression = try! NSRegularExpression(
        pattern: #"^\s*Current week \(([^)]+)\):\s*(\d+(?:\.\d+)?)%\s*used(?:\s*[·•|-]\s*resets\s+(.+?))?\s*$"#,
        options: [.caseInsensitive]
    )

    // "Nov 12 at 12:20pm (Europe/Oslo)", with an optional year after the day.
    private static let resetExpression = try! NSRegularExpression(
        pattern: #"([A-Za-z]{3,9})\.?\s+(\d{1,2})(?:,?\s+(\d{4}))?,?(?:\s+at)?\s+(\d{1,2})(?::(\d{2}))?\s*([ap]m)\b(?:\s*\(([^)]+)\))?"#,
        options: [.caseInsensitive]
    )
}
