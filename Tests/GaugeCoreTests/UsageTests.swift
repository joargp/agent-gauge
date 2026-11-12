import Foundation
import XCTest
@testable import GaugeCore

final class UsageTests: XCTestCase {
    func testRemainingPercentageIsClamped() {
        XCTAssertEqual(makeWindow(used: -8).remainingPercent, 100)
        XCTAssertEqual(makeWindow(used: 40.25).remainingPercent, 59.75)
        XCTAssertEqual(makeWindow(used: 140).remainingPercent, 0)
    }

    func testRolledOverUsesResetsAt() {
        let resetsAt = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(
            UsageWindow(usedPercent: 10, resetsAt: resetsAt)
                .isRolledOver(now: Date(timeIntervalSince1970: 999))
        )
        XCTAssertTrue(
            UsageWindow(usedPercent: 10, resetsAt: resetsAt)
                .isRolledOver(now: Date(timeIntervalSince1970: 1_000))
        )
        XCTAssertFalse(UsageWindow(usedPercent: 10, resetsAt: nil).isRolledOver())
    }

    func testFreshnessThresholds() {
        let capturedAt = Date(timeIntervalSince1970: 0)
        let now = Date(timeIntervalSince1970: 100)

        XCTAssertEqual(DataFreshness(capturedAt: capturedAt, now: now), .live)
        XCTAssertEqual(
            DataFreshness(capturedAt: capturedAt, now: Date(timeIntervalSince1970: 120)),
            .live
        )
        XCTAssertEqual(
            DataFreshness(capturedAt: capturedAt, now: Date(timeIntervalSince1970: 500)),
            .recent
        )
        XCTAssertEqual(
            DataFreshness(capturedAt: capturedAt, now: Date(timeIntervalSince1970: 5_000)),
            .stale
        )
    }

    func testDisplayStateMapping() {
        let now = Date(timeIntervalSince1970: 5_000)
        let fresh = UsageWindow(usedPercent: 20, resetsAt: now.addingTimeInterval(600))
        let rolledOver = UsageWindow(usedPercent: 20, resetsAt: now.addingTimeInterval(-1))
        let snapshot = UsageSnapshot(
            fiveHourWindow: fresh,
            weeklyWindow: nil,
            badge: "2.1.250",
            capturedAt: now
        )

        XCTAssertEqual(snapshot.fiveHourState(now: now), .present(fresh))
        XCTAssertEqual(snapshot.weeklyState(now: now), .awaitingCapture)

        let rolledSnapshot = UsageSnapshot(
            fiveHourWindow: rolledOver,
            weeklyWindow: nil,
            badge: nil,
            capturedAt: now
        )
        XCTAssertEqual(rolledSnapshot.fiveHourState(now: now), .rolledOver)

        let completeSnapshot = UsageSnapshot(
            fiveHourWindow: nil,
            weeklyWindow: fresh,
            badge: nil,
            capturedAt: now,
            absentWindowsHaveNoLimit: true
        )
        XCTAssertEqual(completeSnapshot.fiveHourState(now: now), .noLimit)
        XCTAssertEqual(completeSnapshot.weeklyState(now: now), .present(fresh))
    }

    private func makeWindow(used: Double) -> UsageWindow {
        UsageWindow(usedPercent: used, resetsAt: nil)
    }
}

final class SubLimitTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func snapshot(weeklyUsed: Double, fableUsed: Double?, fableResetsIn: TimeInterval = 3_600) -> UsageSnapshot {
        UsageSnapshot(
            fiveHourWindow: nil,
            weeklyWindow: UsageWindow(usedPercent: weeklyUsed, resetsAt: now.addingTimeInterval(86_400)),
            badge: nil,
            capturedAt: now,
            subLimit: fableUsed.map {
                SubLimit(
                    name: "Fable",
                    window: UsageWindow(usedPercent: $0, resetsAt: now.addingTimeInterval(fableResetsIn))
                )
            }
        )
    }

    func testRunsOutFirstWhenFableHasLessLeft() {
        XCTAssertTrue(snapshot(weeklyUsed: 50, fableUsed: 70).subLimitRunsOutFirst(now: now))
    }

    func testDoesNotRunOutFirstWhenEqualOrHigher() {
        XCTAssertFalse(snapshot(weeklyUsed: 73, fableUsed: 73).subLimitRunsOutFirst(now: now))
        XCTAssertFalse(snapshot(weeklyUsed: 73, fableUsed: 40).subLimitRunsOutFirst(now: now))
        XCTAssertFalse(snapshot(weeklyUsed: 73.2, fableUsed: 72.8).subLimitRunsOutFirst(now: now))
    }

    func testNoSubLimitMeansNothingToShow() {
        let none = snapshot(weeklyUsed: 50, fableUsed: nil)
        XCTAssertNil(none.currentSubLimit(now: now))
        XCTAssertFalse(none.subLimitRunsOutFirst(now: now))
    }

    func testRolledOverSubLimitIsHidden() {
        let rolled = snapshot(weeklyUsed: 10, fableUsed: 90, fableResetsIn: -1)
        XCTAssertNil(rolled.currentSubLimit(now: now))
        XCTAssertFalse(rolled.subLimitRunsOutFirst(now: now))
    }
}
