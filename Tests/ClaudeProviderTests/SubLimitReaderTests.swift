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

    func testBackgroundPollsAtMostEveryFifteenMinutes() async throws {
        let clock = Clock()
        let fetcher = Fetcher(.found(limit(clock: clock)))
        let reader = makeReader(fetcher, clock)
        XCTAssertEqual(SubLimitReader.pollInterval, 900)

        _ = await reader.current(userInitiated: true)
        clock.now.addTimeInterval(SubLimitReader.pollInterval - 1)
        _ = await reader.current(userInitiated: false)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(fetcher.calls, 1)

        clock.now.addTimeInterval(2)
        _ = await reader.current(userInitiated: false)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(fetcher.calls, 2)
    }

    func testUnchangedVerifiedMismatchUsesNormalPollInterval() async throws {
        let clock = Clock()
        let reset = clock.now.addingTimeInterval(3_600)
        let verified = UsageWindow(usedPercent: 54, resetsAt: reset)
        let disagreement = UsageWindow(usedPercent: 92, resetsAt: reset)
        let fetcher = Fetcher(.reading(weekly: verified, fable: nil))
        let reader = makeReader(fetcher, clock)

        _ = await reader.currentReading(userInitiated: true, capturedAt: clock.now, statuslineWeekly: disagreement)
        clock.now.addTimeInterval(61)
        _ = await reader.currentReading(userInitiated: false, capturedAt: clock.now, statuslineWeekly: disagreement)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(fetcher.calls, 1)

        let changed = UsageWindow(usedPercent: 93, resetsAt: reset)
        _ = await reader.currentReading(userInitiated: false, capturedAt: clock.now, statuslineWeekly: changed)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(fetcher.calls, 2)
    }

    func testWeeklyRolloverRechecksEvenWhenStatuslineStillAgrees() async throws {
        let clock = Clock()
        let ending = UsageWindow(usedPercent: 92, resetsAt: clock.now.addingTimeInterval(30))
        let fetcher = Fetcher(.reading(weekly: ending, fable: nil))
        let reader = makeReader(fetcher, clock)

        _ = await reader.currentReading(userInitiated: true, capturedAt: clock.now, statuslineWeekly: ending)
        clock.now.addTimeInterval(61)
        let next = UsageWindow(usedPercent: 1, resetsAt: clock.now.addingTimeInterval(604_800))
        fetcher.outcome = .reading(weekly: next, fable: nil)
        _ = await reader.currentReading(userInitiated: false, capturedAt: clock.now, statuslineWeekly: ending)
        try await Task.sleep(for: .milliseconds(50))
        let reading = await reader.currentReading(userInitiated: false, capturedAt: clock.now, statuslineWeekly: ending)
        XCTAssertEqual(fetcher.calls, 2)
        XCTAssertEqual(reading.weekly, next)

        // A fresh 5-hour capture can keep carrying the expired weekly row.
        // It no longer needs a mismatch check now that the new week is verified.
        clock.now.addTimeInterval(61)
        _ = await reader.currentReading(userInitiated: false, capturedAt: clock.now, statuslineWeekly: ending)
        clock.now.addTimeInterval(1)
        let refreshed = await reader.currentReading(userInitiated: true, capturedAt: clock.now, statuslineWeekly: ending)
        XCTAssertEqual(refreshed.checkStartedAt, clock.now, "Only the manual refresh should start a new check")
        XCTAssertEqual(fetcher.calls, 3)
    }

    func testExpiredWeeklyRowDoesNotClearRejectionsAndAllowsRolloverRetry() async throws {
        let clock = Clock()
        let start = clock.now
        let ending = UsageWindow(usedPercent: 54, resetsAt: start.addingTimeInterval(66))
        let resetless = UsageWindow(usedPercent: ending.usedPercent, resetsAt: nil)
        let fable = limit(clock: clock)
        let fetcher = Fetcher(.reading(weekly: UsageWindow(usedPercent: 92, resetsAt: ending.resetsAt), fable: nil))
        let reader = SubLimitReader(fetch: {
            if clock.now == start.addingTimeInterval(61) { clock.now.addTimeInterval(5) }
            return await fetcher.fetch()
        }, now: { clock.now })

        let first = await reader.currentReading(userInitiated: true, capturedAt: start, statuslineWeekly: resetless)
        XCTAssertTrue(first.rejects(resetless))

        clock.now = start.addingTimeInterval(61)
        fetcher.outcome = .reading(weekly: ending, fable: fable)
        let expired = await reader.currentReading(userInitiated: true, capturedAt: clock.now, statuslineWeekly: resetless)
        XCTAssertNil(expired.weekly)
        XCTAssertEqual(expired.fable, fable)
        XCTAssertTrue(expired.rejects(resetless), "An expired row cannot confirm a rejected reading")

        // Rollover still permits an early retry on new status-line activity,
        // even without a weekly row in that status-line capture.
        clock.now = start.addingTimeInterval(122)
        let next = UsageWindow(usedPercent: 4, resetsAt: clock.now.addingTimeInterval(604_800))
        fetcher.outcome = .reading(weekly: next, fable: fable)
        _ = await reader.currentReading(userInitiated: false, capturedAt: clock.now)
        try await Task.sleep(for: .milliseconds(50))
        let recovered = await reader.reconcile(statuslineWeekly: nil, capturedAt: nil)
        XCTAssertEqual(fetcher.calls, 3)
        XCTAssertEqual(recovered.weekly, next)
    }

    func testIncompleteCheckRetriesEveryMinuteWhileTheStatuslineReadingIsRejected() async throws {
        let clock = Clock()
        let reset = clock.now.addingTimeInterval(86_400)
        let stale = UsageWindow(usedPercent: 54, resetsAt: reset)
        let fetcher = Fetcher(.reading(weekly: UsageWindow(usedPercent: 92, resetsAt: reset), fable: nil))
        let reader = makeReader(fetcher, clock)
        let first = await reader.currentReading(userInitiated: true, capturedAt: clock.now, statuslineWeekly: stale)
        XCTAssertTrue(first.rejects(stale))

        // /usage prints no all-models row, so nothing replaces the rejected reading.
        clock.now.addTimeInterval(61)
        fetcher.outcome = .found(limit(clock: clock))
        var captured = clock.now
        let incomplete = await reader.currentReading(userInitiated: true, capturedAt: captured, statuslineWeekly: stale)
        XCTAssertNil(incomplete.weekly)
        XCTAssertTrue(incomplete.rejects(stale))
        XCTAssertEqual(fetcher.calls, 2)

        // Claude Code idle: no new capture, no run.
        clock.now.addTimeInterval(61)
        _ = await reader.currentReading(userInitiated: false, capturedAt: captured, statuslineWeekly: stale)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(fetcher.calls, 2)

        // New activity a minute later: one run, never two at once.
        fetcher.delay = .milliseconds(200)
        captured = clock.now
        _ = await reader.currentReading(userInitiated: false, capturedAt: captured, statuslineWeekly: stale)
        _ = await reader.currentReading(userInitiated: false, capturedAt: captured.addingTimeInterval(10), statuslineWeekly: stale)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(fetcher.calls, 3)

        // Still at most once a minute.
        fetcher.delay = .zero
        clock.now.addTimeInterval(30)
        captured = clock.now
        _ = await reader.currentReading(userInitiated: false, capturedAt: captured, statuslineWeekly: stale)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(fetcher.calls, 3)

        clock.now.addTimeInterval(31)
        captured = clock.now
        fetcher.outcome = .reading(weekly: UsageWindow(usedPercent: 93, resetsAt: reset), fable: nil)
        _ = await reader.currentReading(userInitiated: false, capturedAt: captured, statuslineWeekly: stale)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(fetcher.calls, 4)
        let recovered = await reader.reconcile(statuslineWeekly: stale, capturedAt: captured)
        XCTAssertEqual(recovered.weekly?.usedPercent, 93)

        // A checked value is back, so the rejected reading is no longer urgent.
        clock.now.addTimeInterval(61)
        _ = await reader.currentReading(userInitiated: false, capturedAt: clock.now, statuslineWeekly: stale)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(fetcher.calls, 4)
    }

    func testIncompleteCheckKeepsNormalCadenceWhenNothingIsRejected() async throws {
        let clock = Clock()
        let reset = clock.now.addingTimeInterval(86_400)
        let statusline = UsageWindow(usedPercent: 92, resetsAt: reset)
        let fetcher = Fetcher(.reading(weekly: statusline, fable: nil))
        let reader = makeReader(fetcher, clock)
        _ = await reader.currentReading(userInitiated: true, capturedAt: clock.now, statuslineWeekly: statusline)

        clock.now.addTimeInterval(61)
        fetcher.outcome = .found(limit(clock: clock))
        let start = clock.now
        let incomplete = await reader.currentReading(userInitiated: true, capturedAt: clock.now, statuslineWeekly: statusline)
        XCTAssertNil(incomplete.weekly)
        XCTAssertFalse(incomplete.rejects(statusline))

        clock.now.addTimeInterval(61)
        _ = await reader.currentReading(userInitiated: false, capturedAt: clock.now, statuslineWeekly: statusline)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(fetcher.calls, 2, "The status line's reading still shows, so no hurry")

        clock.now = start.addingTimeInterval(SubLimitReader.pollInterval)
        _ = await reader.currentReading(userInitiated: false, capturedAt: clock.now, statuslineWeekly: statusline)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(fetcher.calls, 3)
    }

    func testReconcileJudgesReadingsByWhenTheyWereCaptured() async {
        let clock = Clock()
        // A multiple of the capture rounding step, like every capture time.
        let start = clock.now
        XCTAssertEqual(start.timeIntervalSince1970.truncatingRemainder(dividingBy: CaptureRunner.capturedAtRounding), 0)
        let reset = start.addingTimeInterval(86_400)
        // The check takes 25 seconds.
        let reader = SubLimitReader(fetch: {
            clock.now.addTimeInterval(25)
            return .reading(weekly: UsageWindow(usedPercent: 92, resetsAt: reset), fable: nil)
        }, now: { clock.now })
        _ = await reader.currentReading(userInitiated: true, capturedAt: start)

        func rejected(_ used: Double, capturedAt offset: TimeInterval) async -> Bool {
            let window = UsageWindow(usedPercent: used, resetsAt: reset)
            return await reader.reconcile(
                statuslineWeekly: window, capturedAt: start.addingTimeInterval(offset)
            ).rejects(window)
        }
        // Each capture happened within ten seconds after its time. The CLI
        // fetched its value at some unknown moment within the 25 seconds.
        let beforeAhead = await rejected(95, capturedAt: -10)
        let beforeBehind = await rejected(50, capturedAt: -20)
        let straddlingStartAhead = await rejected(96, capturedAt: -5)
        let straddlingStartBehind = await rejected(51, capturedAt: -5)
        let duringAhead = await rejected(97, capturedAt: 10)
        let duringBehind = await rejected(52, capturedAt: 10)
        let straddlingEndBehind = await rejected(53, capturedAt: 20)
        let after = await rejected(54, capturedAt: 30)
        XCTAssertTrue(beforeAhead, "Older than the check")
        XCTAssertTrue(beforeBehind, "Older than the check")
        XCTAssertFalse(straddlingStartAhead, "May be usage the check predates")
        XCTAssertFalse(straddlingStartBehind, "May be a correction the check predates")
        XCTAssertFalse(duringAhead, "May be usage the check predates")
        XCTAssertFalse(duringBehind, "May be a correction the check predates")
        XCTAssertFalse(straddlingEndBehind, "May have been captured after the check finished")
        XCTAssertFalse(after, "Newer than the check")
    }

    func testReadingWithoutCaptureTimeIsNeverRejected() async {
        let clock = Clock()
        let reset = clock.now.addingTimeInterval(86_400)
        let reader = makeReader(Fetcher(.reading(weekly: UsageWindow(usedPercent: 92, resetsAt: reset), fable: nil)), clock)
        _ = await reader.currentReading(userInitiated: true, capturedAt: clock.now)

        let behind = UsageWindow(usedPercent: 50, resetsAt: reset)
        let ahead = UsageWindow(usedPercent: 95, resetsAt: reset)
        let behindReading = await reader.reconcile(statuslineWeekly: behind, capturedAt: nil)
        let aheadReading = await reader.reconcile(statuslineWeekly: ahead, capturedAt: nil)
        XCTAssertFalse(behindReading.rejects(behind))
        XCTAssertFalse(aheadReading.rejects(ahead))
    }

    /// The CLI finishes at 12:00:03. A genuine correction captured at
    /// 12:00:05 is stamped 12:00:00, before the check ended.
    func testCorrectionStampedBeforeTheCheckEndedCanFallBackAfterFailure() async {
        let clock = Clock()
        let start = clock.now
        let reset = start.addingTimeInterval(86_400)
        let fetcher = Fetcher(.reading(weekly: UsageWindow(usedPercent: 92, resetsAt: reset), fable: nil))
        let reader = SubLimitReader(fetch: {
            clock.now.addTimeInterval(3)
            return await fetcher.fetch()
        }, now: { clock.now })
        _ = await reader.currentReading(userInitiated: true, capturedAt: start)

        clock.now = start.addingTimeInterval(5)
        let correction = UsageWindow(usedPercent: 54, resetsAt: reset)
        let settled = await reader.reconcile(statuslineWeekly: correction, capturedAt: start)
        XCTAssertFalse(settled.rejects(correction))
        XCTAssertEqual(
            settled.verifiedWeekly(over: correction, capturedAt: start)?.0.usedPercent, 92,
            "A successful check still stands"
        )

        clock.now = start.addingTimeInterval(61)
        fetcher.outcome = .failed
        _ = await reader.currentReading(userInitiated: true, capturedAt: start, statuslineWeekly: correction)
        let failed = await reader.reconcile(statuslineWeekly: correction, capturedAt: start)
        XCTAssertEqual(fetcher.calls, 2)
        XCTAssertFalse(failed.rejects(correction))
        XCTAssertNil(failed.verifiedWeekly(over: correction, capturedAt: start), "The correction shows instead")
    }

    /// The check runs from 12:00:00 to 12:00:15, and the CLI asked
    /// Anthropic for usage early in that run. A status-line reading stamped
    /// 12:00:00 ended before the check did, but may still be newer than the
    /// CLI's value, whether it shows more usage or less.
    func testReadingCapturedWhileTheCheckRanFallsBackAfterFailure() async {
        for used in [95.0, 54.0] {
            let clock = Clock()
            let start = clock.now
            let reset = start.addingTimeInterval(86_400)
            let verified = UsageWindow(usedPercent: 92, resetsAt: reset)
            let fetcher = Fetcher(.reading(weekly: verified, fable: nil))
            let reader = SubLimitReader(fetch: {
                clock.now.addTimeInterval(15)
                return await fetcher.fetch()
            }, now: { clock.now })
            _ = await reader.currentReading(userInitiated: true, capturedAt: start)

            let during = UsageWindow(usedPercent: used, resetsAt: reset)
            let settled = await reader.reconcile(statuslineWeekly: during, capturedAt: start)
            XCTAssertFalse(settled.rejects(during), "\(used)%")
            XCTAssertEqual(
                settled.verifiedWeekly(over: during, capturedAt: start)?.0, verified,
                "A successful check still stands, \(used)%"
            )

            clock.now = start.addingTimeInterval(61)
            fetcher.outcome = .failed
            _ = await reader.currentReading(userInitiated: true, capturedAt: start, statuslineWeekly: during)
            let failed = await reader.reconcile(statuslineWeekly: during, capturedAt: start)
            XCTAssertEqual(fetcher.calls, 2)
            XCTAssertFalse(failed.rejects(during), "\(used)%")
            XCTAssertNil(failed.verifiedWeekly(over: during, capturedAt: start), "The reading shows instead, \(used)%")
        }
    }

    func testReadingCapturedBeforeTheCheckStartedDoesNotFallBackAfterFailure() async {
        let clock = Clock()
        let start = clock.now
        let reset = start.addingTimeInterval(86_400)
        let verified = UsageWindow(usedPercent: 92, resetsAt: reset)
        let fetcher = Fetcher(.reading(weekly: verified, fable: nil))
        let reader = makeReader(fetcher, clock)
        _ = await reader.currentReading(userInitiated: true, capturedAt: start)

        // Agrees with the check, so it is not rejected, but it is older.
        let older = UsageWindow(usedPercent: 92.5, resetsAt: reset)
        let capturedAt = start.addingTimeInterval(-CaptureRunner.capturedAtRounding)
        clock.now = start.addingTimeInterval(61)
        fetcher.outcome = .failed
        _ = await reader.currentReading(userInitiated: true, capturedAt: capturedAt, statuslineWeekly: older)
        let failed = await reader.reconcile(statuslineWeekly: older, capturedAt: capturedAt)
        XCTAssertFalse(failed.rejects(older))
        XCTAssertEqual(failed.verifiedWeekly(over: older, capturedAt: capturedAt)?.0, verified)
    }

    func testKnownRejectedRedrawCapturedDuringALaterCheckDoesNotFallBack() async {
        let clock = Clock()
        let start = clock.now
        let reset = start.addingTimeInterval(86_400)
        let verified = UsageWindow(usedPercent: 92, resetsAt: reset)
        let stale = UsageWindow(usedPercent: 54, resetsAt: reset)
        let fetcher = Fetcher(.reading(weekly: verified, fable: nil))
        let reader = makeReader(fetcher, clock)
        let first = await reader.currentReading(userInitiated: true, capturedAt: start, statuslineWeekly: stale)
        XCTAssertTrue(first.rejects(stale))

        // The idle session redraws it while a later check runs; the check
        // succeeds and a following one fails.
        clock.now = start.addingTimeInterval(61)
        _ = await reader.currentReading(userInitiated: true, capturedAt: start, statuslineWeekly: stale)
        _ = await reader.reconcile(statuslineWeekly: stale, capturedAt: clock.now)
        clock.now = start.addingTimeInterval(122)
        fetcher.outcome = .failed
        _ = await reader.currentReading(userInitiated: true, capturedAt: clock.now, statuslineWeekly: stale)
        let failed = await reader.reconcile(statuslineWeekly: stale, capturedAt: clock.now)
        XCTAssertEqual(fetcher.calls, 3)
        XCTAssertTrue(failed.rejects(stale))
        XCTAssertEqual(failed.verifiedWeekly(over: stale, capturedAt: clock.now)?.0, verified)
    }

    func testOldEvidenceDoesNotRejectNewUsageWhileACheckRuns() async throws {
        let clock = Clock()
        let reset = clock.now.addingTimeInterval(86_400)
        let fetcher = Fetcher(.reading(weekly: UsageWindow(usedPercent: 92, resetsAt: reset), fable: nil))
        let reader = makeReader(fetcher, clock)
        _ = await reader.currentReading(userInitiated: true, capturedAt: clock.now)

        clock.now.addTimeInterval(61)
        let current = UsageWindow(usedPercent: 50, resetsAt: reset)
        fetcher.outcome = .reading(weekly: current, fable: nil)
        fetcher.delay = .milliseconds(200)
        _ = await reader.currentReading(userInitiated: false, capturedAt: clock.now, statuslineWeekly: current)
        let pending = await reader.reconcile(statuslineWeekly: current, capturedAt: clock.now)
        XCTAssertFalse(pending.rejects(current))

        try await Task.sleep(for: .milliseconds(400))
        let settled = await reader.reconcile(statuslineWeekly: current, capturedAt: clock.now)
        XCTAssertEqual(settled.weekly, current)
        XCTAssertFalse(settled.rejects(current))
    }

    func testRejectionEndsWithItsOwnWindow() async {
        let clock = Clock()
        let verified = UsageWindow(usedPercent: 92, resetsAt: clock.now.addingTimeInterval(86_400))
        let stale = UsageWindow(usedPercent: 40, resetsAt: clock.now.addingTimeInterval(100))
        let reader = makeReader(Fetcher(.reading(weekly: verified, fable: nil)), clock)

        let reading = await reader.currentReading(userInitiated: true, capturedAt: clock.now, statuslineWeekly: stale)
        XCTAssertTrue(reading.rejects(stale))
        clock.now.addTimeInterval(120)
        let later = await reader.reconcile(statuslineWeekly: nil, capturedAt: nil)
        XCTAssertTrue(later.rejectedStatuslineWeeklies.isEmpty)
    }

    func testMoreThanSixteenRejectionsStayRejectedAcrossFailedAndIncompleteChecks() async throws {
        let clock = Clock()
        let start = clock.now
        let reset = start.addingTimeInterval(86_400)
        let verified = UsageWindow(usedPercent: 92, resetsAt: reset)
        let fetcher = Fetcher(.reading(weekly: verified, fable: nil))
        let reader = makeReader(fetcher, clock)
        let stale = (30..<50).map { UsageWindow(usedPercent: Double($0), resetsAt: reset) }

        for window in stale {
            _ = await reader.currentReading(userInitiated: true, capturedAt: clock.now, statuslineWeekly: window)
            clock.now.addTimeInterval(61)
        }

        let oldest = try XCTUnwrap(stale.first)
        fetcher.outcome = .failed
        // It was redrawn after the last successful check, so that check
        // can't just re-reject it based on the new capture timestamp.
        let failed = await reader.currentReading(userInitiated: true, capturedAt: clock.now, statuslineWeekly: oldest)
        XCTAssertTrue(stale.allSatisfy { failed.rejects($0) })
        XCTAssertEqual(failed.verifiedWeekly(over: oldest, capturedAt: clock.now)?.0, verified)

        clock.now.addTimeInterval(61)
        fetcher.outcome = .absent
        let incomplete = await reader.currentReading(userInitiated: true, capturedAt: clock.now, statuslineWeekly: oldest)
        XCTAssertNil(incomplete.weekly)
        XCTAssertTrue(stale.allSatisfy { incomplete.rejects($0) })

        clock.now.addTimeInterval(61)
        fetcher.outcome = .reading(weekly: oldest, fable: nil)
        let confirmed = await reader.currentReading(userInitiated: true, capturedAt: clock.now, statuslineWeekly: oldest)
        XCTAssertFalse(confirmed.rejects(oldest))
        XCTAssertTrue(stale.dropFirst().allSatisfy { confirmed.rejects($0) })

        clock.now = reset
        let rolledOver = await reader.reconcile(statuslineWeekly: nil, capturedAt: nil)
        XCTAssertTrue(rolledOver.rejectedStatuslineWeeklies.isEmpty)
    }

    func testResetlessRejectionExpiresOneWeekAfterLastContradictingCheck() async {
        let clock = Clock()
        let start = clock.now
        let week: TimeInterval = 7 * 24 * 60 * 60
        let verified = UsageWindow(usedPercent: 92, resetsAt: start.addingTimeInterval(120))
        let fetcher = Fetcher(.reading(weekly: verified, fable: nil))
        let reader = makeReader(fetcher, clock)
        let stale = UsageWindow(usedPercent: 40, resetsAt: nil)
        let other = UsageWindow(usedPercent: 50, resetsAt: nil)

        let first = await reader.currentReading(userInitiated: true, capturedAt: start, statuslineWeekly: stale)
        XCTAssertTrue(first.rejects(stale))
        let beforeCheck = await reader.reconcile(statuslineWeekly: other, capturedAt: start.addingTimeInterval(-10))
        XCTAssertTrue(beforeCheck.rejects(other))

        clock.now = start.addingTimeInterval(61)
        _ = await reader.currentReading(userInitiated: true, capturedAt: clock.now, statuslineWeekly: stale)
        clock.now = start.addingTimeInterval(122)
        fetcher.outcome = .absent
        let afterReset = await reader.currentReading(userInitiated: true, capturedAt: clock.now, statuslineWeekly: other)
        XCTAssertNil(afterReset.weekly)
        XCTAssertTrue(afterReset.rejects(stale))
        XCTAssertTrue(afterReset.rejects(other), "The checked value's reset is not the status-line reading's reset")

        clock.now = start.addingTimeInterval(week - 1)
        let redrawn = await reader.reconcile(statuslineWeekly: other, capturedAt: clock.now)
        XCTAssertTrue(redrawn.rejects(other))
        clock.now = start.addingTimeInterval(week)
        let oneWeek = await reader.reconcile(statuslineWeekly: other, capturedAt: clock.now)
        XCTAssertFalse(oneWeek.rejects(other), "A redraw alone does not extend the rejection")
        XCTAssertTrue(oneWeek.rejects(stale), "A newer contradicting check does extend it")

        clock.now = start.addingTimeInterval(week + 61)
        let later = await reader.reconcile(statuslineWeekly: stale, capturedAt: clock.now)
        XCTAssertFalse(later.rejects(stale))
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
