import Foundation
import XCTest
@testable import ClaudeProvider
import GaugeCore

final class SubLimitReaderTests: XCTestCase {
    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_000_000)
    }

    private final class Fetcher: @unchecked Sendable {
        private let lock = NSLock()
        private var _calls = 0
        var outcome: SubLimitReader.Outcome
        var delay: Duration = .zero

        init(_ outcome: SubLimitReader.Outcome) { self.outcome = outcome }

        var calls: Int { lock.withLock { _calls } }

        func fetch() async -> SubLimitReader.Outcome {
            lock.withLock { _calls += 1 }
            if delay > .zero { try? await Task.sleep(for: delay) }
            return outcome
        }
    }

    private func limit(resetsIn seconds: TimeInterval = 36_000, clock: Clock) -> SubLimit {
        SubLimit(
            name: "Fable",
            window: UsageWindow(usedPercent: 30, resetsAt: clock.now.addingTimeInterval(seconds))
        )
    }

    private func makeReader(_ fetcher: Fetcher, _ clock: Clock) -> SubLimitReader {
        SubLimitReader(fetch: { await fetcher.fetch() }, now: { clock.now })
    }

    func testUserRefreshWaitsForTheReading() async {
        let clock = Clock()
        let fetcher = Fetcher(.found(limit(clock: clock)))
        let reader = makeReader(fetcher, clock)

        let result = await reader.current(userInitiated: true)

        XCTAssertEqual(result?.name, "Fable")
        XCTAssertEqual(fetcher.calls, 1)
    }

    func testBackgroundPollReturnsWithoutWaiting() async throws {
        let clock = Clock()
        let fetcher = Fetcher(.found(limit(clock: clock)))
        fetcher.delay = .milliseconds(200)
        let reader = makeReader(fetcher, clock)

        let first = await reader.current(userInitiated: false)
        XCTAssertNil(first)

        try await Task.sleep(for: .milliseconds(500))
        let second = await reader.current(userInitiated: false)
        XCTAssertEqual(second?.name, "Fable")
        XCTAssertEqual(fetcher.calls, 1)
    }

    func testPollsAtMostEveryFiveMinutes() async {
        let clock = Clock()
        let fetcher = Fetcher(.found(limit(clock: clock)))
        let reader = makeReader(fetcher, clock)

        _ = await reader.current(userInitiated: true)
        clock.now.addTimeInterval(299)
        _ = await reader.current(userInitiated: false)
        XCTAssertEqual(fetcher.calls, 1)

        clock.now.addTimeInterval(2)
        _ = await reader.current(userInitiated: true)
        XCTAssertEqual(fetcher.calls, 2)
    }

    func testRefreshIsLimitedToOncePerMinute() async {
        let clock = Clock()
        let fetcher = Fetcher(.found(limit(clock: clock)))
        let reader = makeReader(fetcher, clock)

        _ = await reader.current(userInitiated: true)
        clock.now.addTimeInterval(30)
        _ = await reader.current(userInitiated: true)
        XCTAssertEqual(fetcher.calls, 1)

        clock.now.addTimeInterval(31)
        _ = await reader.current(userInitiated: true)
        XCTAssertEqual(fetcher.calls, 2)
    }

    func testNeverRunsConcurrently() async {
        let clock = Clock()
        let fetcher = Fetcher(.found(limit(clock: clock)))
        fetcher.delay = .milliseconds(200)
        let reader = makeReader(fetcher, clock)

        async let a = reader.current(userInitiated: true)
        async let b = reader.current(userInitiated: true)
        _ = await (a, b)

        XCTAssertEqual(fetcher.calls, 1)
    }

    func testFailureKeepsLastReadingButAbsentClearsIt() async {
        let clock = Clock()
        let fetcher = Fetcher(.found(limit(clock: clock)))
        let reader = makeReader(fetcher, clock)
        _ = await reader.current(userInitiated: true)

        clock.now.addTimeInterval(400)
        fetcher.outcome = .failed
        let afterFailure = await reader.current(userInitiated: true)
        XCTAssertEqual(afterFailure?.name, "Fable")

        clock.now.addTimeInterval(400)
        fetcher.outcome = .absent
        let afterAbsent = await reader.current(userInitiated: true)
        XCTAssertNil(afterAbsent)
    }

    func testLongFailureStreakHidesTheReading() async {
        let clock = Clock()
        let fetcher = Fetcher(.found(limit(clock: clock)))
        let reader = makeReader(fetcher, clock)
        _ = await reader.current(userInitiated: true)

        fetcher.outcome = .failed
        clock.now.addTimeInterval(400)
        let shortlyAfter = await reader.current(userInitiated: true)
        XCTAssertEqual(shortlyAfter?.name, "Fable", "One failed run keeps the reading")

        clock.now.addTimeInterval(SubLimitReader.staleAfterFailures)
        let muchLater = await reader.current(userInitiated: true)
        XCTAssertNil(muchLater, "Thirty minutes of failures hides it")

        fetcher.outcome = .found(limit(clock: clock))
        clock.now.addTimeInterval(61)
        let recovered = await reader.current(userInitiated: true)
        XCTAssertEqual(recovered?.name, "Fable")
    }

    func testOldReadingStaysWhileNothingFails() async {
        let clock = Clock()
        let fetcher = Fetcher(.found(limit(clock: clock)))
        let reader = makeReader(fetcher, clock)
        let captured = clock.now
        _ = await reader.current(userInitiated: true, capturedAt: captured)

        // Claude Code idle: no new capture, so no runs and nothing failing.
        clock.now.addTimeInterval(SubLimitReader.staleAfterFailures * 4)
        let result = await reader.current(userInitiated: false, capturedAt: captured)

        XCTAssertEqual(result?.name, "Fable")
        XCTAssertEqual(fetcher.calls, 1)
    }

    func testBackgroundPollsWaitForNewClaudeActivity() async throws {
        let clock = Clock()
        let fetcher = Fetcher(.found(limit(clock: clock)))
        let reader = makeReader(fetcher, clock)
        let first = clock.now

        _ = await reader.current(userInitiated: false, capturedAt: first)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(fetcher.calls, 1)

        clock.now.addTimeInterval(SubLimitReader.pollInterval + 1)
        _ = await reader.current(userInitiated: false, capturedAt: first)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(fetcher.calls, 1, "Same capture: Claude Code is idle, so no run")

        _ = await reader.current(userInitiated: false, capturedAt: first.addingTimeInterval(200))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(fetcher.calls, 2, "New capture: run again")

        clock.now.addTimeInterval(SubLimitReader.refreshInterval + 1)
        _ = await reader.current(userInitiated: true, capturedAt: first.addingTimeInterval(200))
        XCTAssertEqual(fetcher.calls, 3, "Refresh always runs")
    }

    func testFailureWithoutReadingGivesNil() async {
        let clock = Clock()
        let reader = makeReader(Fetcher(.failed), clock)

        let result = await reader.current(userInitiated: true)

        XCTAssertNil(result)
    }

    func testRolledOverReadingIsDropped() async {
        let clock = Clock()
        let fetcher = Fetcher(.found(limit(resetsIn: 100, clock: clock)))
        let reader = makeReader(fetcher, clock)
        _ = await reader.current(userInitiated: true)

        clock.now.addTimeInterval(120)
        let result = await reader.current(userInitiated: false)

        XCTAssertNil(result)
    }
}
