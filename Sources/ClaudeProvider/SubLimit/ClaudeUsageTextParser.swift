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

    /// The Fable weekly window from the `/usage` text, or nil when the text
    /// has no such line (a plan without a Fable cap, or API-key output).
    public static func parseFable(_ text: String, now: Date = Date()) -> SubLimit? {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let match = lineExpression.firstMatch(
                in: line, range: NSRange(line.startIndex..., in: line)
            ),
                  let name = capture(1, in: match, of: line),
                  name.lowercased().hasPrefix("fable"),
                  let used = capture(2, in: match, of: line).flatMap(Double.init),
                  used.isFinite
            else { continue }

            let resetsAt = capture(3, in: match, of: line).flatMap { parseReset($0, now: now) }
            return SubLimit(
                name: name,
                window: UsageWindow(usedPercent: min(100, max(0, used)), resetsAt: resetsAt)
            )
        }
        return nil
    }

    /// Parses "Nov 12 at 8pm", "Nov 12 at 12:20pm (Europe/Oslo)" and
    /// "Nov 12, 2027 at 8pm". Without a year, the next matching date is used.
    static func parseReset(_ text: String, now: Date) -> Date? {
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

        var calendar = Calendar(identifier: .gregorian)
        if let identifier = capture(7, in: match, of: text),
           let zone = TimeZone(identifier: identifier) {
            calendar.timeZone = zone
        }

        let explicitYear = capture(3, in: match, of: text).flatMap(Int.init)
        let currentYear = calendar.component(.year, from: now)

        func date(year: Int) -> Date? {
            let components = DateComponents(
                year: year, month: month, day: day, hour: hour, minute: minute
            )
            guard let date = calendar.date(from: components),
                  calendar.component(.month, from: date) == month,
                  calendar.component(.day, from: date) == day
            else { return nil }
            return date
        }

        if let explicitYear { return date(year: explicitYear) }
        guard let thisYear = date(year: currentYear) else { return nil }
        // A date more than a day in the past means the next year's.
        if thisYear < now.addingTimeInterval(-86_400) {
            return date(year: currentYear + 1) ?? thisYear
        }
        return thisYear
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
