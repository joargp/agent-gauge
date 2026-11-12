import Foundation
import XCTest
@testable import ClaudeProvider
import GaugeCore

final class ClaudeUsageTextParserTests: XCTestCase {
    private let oslo = TimeZone(identifier: "Europe/Oslo")!

    /// 2026-11-12 10:00 in Oslo.
    private var now: Date { date(2026, 11, 12, 10, 0) }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = oslo
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    private func usageText(fableLine: String?) -> String {
        var lines = [
            "You are currently using your subscription to power your Claude Code usage",
            "",
            "Current session: 28% used · resets Nov 12 at 12:20pm (Europe/Oslo)",
            "Current week (all models): 73% used · resets Nov 12 at 8pm (Europe/Oslo)"
        ]
        if let fableLine { lines.append(fableLine) }
        lines.append(contentsOf: ["", "What's contributing to your usage?"])
        return lines.joined(separator: "\n")
    }

    func testParsesFableLine() throws {
        let text = usageText(
            fableLine: "Current week (Fable): 73% used · resets Nov 12 at 8pm (Europe/Oslo)"
        )

        let fable = try XCTUnwrap(ClaudeUsageTextParser.parseFable(text, now: now))

        XCTAssertEqual(fable.name, "Fable")
        XCTAssertEqual(fable.window.usedPercent, 73)
        XCTAssertEqual(fable.window.resetsAt, date(2026, 11, 12, 20, 0))
    }

    func testNoFableLineGivesNil() {
        let text = usageText(fableLine: nil)

        XCTAssertNil(ClaudeUsageTextParser.parseFable(text, now: now))
    }

    func testOtherWeeklyLinesAreNotFable() {
        let text = usageText(
            fableLine: "Current week (Sonnet only): 12% used · resets Nov 12 at 8pm (Europe/Oslo)"
        )

        XCTAssertNil(ClaudeUsageTextParser.parseFable(text, now: now))
    }

    func testApiKeyOutputGivesNil() {
        let text = """
        You are currently using your API key to power your Claude Code usage

        Total cost: $0.0000
        Total duration (API): 0s
        Usage: 0 input, 0 output, 0 cache read, 0 cache write
        """

        XCTAssertNil(ClaudeUsageTextParser.parseFable(text, now: now))
    }

    func testMissingResetKeepsPercent() throws {
        let fable = try XCTUnwrap(
            ClaudeUsageTextParser.parseFable("Current week (Fable): 40% used", now: now)
        )

        XCTAssertEqual(fable.window.usedPercent, 40)
        XCTAssertNil(fable.window.resetsAt)
    }

    func testUnparseableResetKeepsPercent() throws {
        let fable = try XCTUnwrap(ClaudeUsageTextParser.parseFable(
            "Current week (Fable): 40% used · resets sometime soon", now: now
        ))

        XCTAssertEqual(fable.window.usedPercent, 40)
        XCTAssertNil(fable.window.resetsAt)
    }

    func testParsesTwelveHourTimeWithMinutes() throws {
        let fable = try XCTUnwrap(ClaudeUsageTextParser.parseFable(
            "Current week (Fable): 5% used · resets Nov 12 at 12:20pm (Europe/Oslo)", now: now
        ))

        XCTAssertEqual(fable.window.resetsAt, date(2026, 11, 12, 12, 20))
    }

    func testTwelveAmIsMidnight() throws {
        let fable = try XCTUnwrap(ClaudeUsageTextParser.parseFable(
            "Current week (Fable): 5% used · resets Nov 13 at 12am (Europe/Oslo)", now: now
        ))

        XCTAssertEqual(fable.window.resetsAt, date(2026, 11, 13, 0, 0))
    }

    func testParsesResetOnTheHour() throws {
        let fable = try XCTUnwrap(ClaudeUsageTextParser.parseFable(
            "Current week (Fable): 5% used · resets Nov 14 at 8am (Europe/Oslo)", now: now
        ))

        XCTAssertEqual(fable.window.resetsAt, date(2026, 11, 14, 8, 0))
    }

    func testUsesTimeZoneFromText() throws {
        let fable = try XCTUnwrap(ClaudeUsageTextParser.parseFable(
            "Current week (Fable): 5% used · resets Nov 12 at 8pm (UTC)", now: now
        ))

        XCTAssertEqual(fable.window.resetsAt, Date(timeIntervalSince1970: 1_794_513_600))
    }

    func testResetWithoutZoneUsesCurrentZone() throws {
        let fable = try XCTUnwrap(ClaudeUsageTextParser.parseFable(
            "Current week (Fable): 5% used · resets Nov 12 at 8pm", now: now
        ))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let expected = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 12, hour: 20, minute: 0
        ))
        XCTAssertEqual(fable.window.resetsAt, expected)
    }

    func testParsesExplicitYear() throws {
        let fable = try XCTUnwrap(ClaudeUsageTextParser.parseFable(
            "Current week (Fable): 5% used · resets Jan 3, 2027 at 9:30am (Europe/Oslo)", now: now
        ))

        XCTAssertEqual(fable.window.resetsAt, date(2027, 1, 3, 9, 30))
    }

    func testResetWithoutYearRollsIntoNextYear() throws {
        let december = date(2026, 12, 30, 10, 0)
        let fable = try XCTUnwrap(ClaudeUsageTextParser.parseFable(
            "Current week (Fable): 5% used · resets Jan 3 at 9am (Europe/Oslo)", now: december
        ))

        XCTAssertEqual(fable.window.resetsAt, date(2027, 1, 3, 9, 0))
    }

    func testNamedVariantsAreMatched() throws {
        let fable = try XCTUnwrap(ClaudeUsageTextParser.parseFable(
            "Current week (Fable 5): 10% used · resets Nov 12 at 8pm (Europe/Oslo)", now: now
        ))

        XCTAssertEqual(fable.name, "Fable 5")
    }

    func testResultTextFromJSON() {
        let json = Data(#"{"type":"result","result":"hello","local_command":"usage"}"#.utf8)

        XCTAssertEqual(ClaudeUsageTextParser.resultText(fromJSON: json), "hello")
        XCTAssertNil(ClaudeUsageTextParser.resultText(fromJSON: Data("not json".utf8)))
    }
}
