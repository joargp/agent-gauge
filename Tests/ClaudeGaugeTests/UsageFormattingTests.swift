import Foundation
import XCTest
@testable import ClaudeGaugeCore

final class UsageFormattingTests: XCTestCase {
    func testWholePercentRoundsAndClamps() {
        XCTAssertEqual(UsageFormatting.wholePercent(-10), 0)
        XCTAssertEqual(UsageFormatting.wholePercent(12.4), 12)
        XCTAssertEqual(UsageFormatting.wholePercent(12.6), 13)
        XCTAssertEqual(UsageFormatting.wholePercent(120), 100)
    }

    func testResetDescriptions() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(UsageFormatting.resetDescription(resetsAt: nil, now: now), "Reset time unavailable")
        XCTAssertEqual(
            UsageFormatting.resetDescription(resetsAt: now.addingTimeInterval(30), now: now),
            "Resets in 1m"
        )
        XCTAssertEqual(
            UsageFormatting.resetDescription(resetsAt: now.addingTimeInterval(3_900), now: now),
            "Resets in 1h 5m"
        )
        XCTAssertEqual(
            UsageFormatting.resetDescription(resetsAt: now.addingTimeInterval(90_000), now: now),
            "Resets in 1d 1h"
        )
        XCTAssertEqual(
            UsageFormatting.resetDescription(resetsAt: now, now: now),
            "Resetting now"
        )
    }

    func testLastUpdatedDescriptionsIncludeDays() {
        let now = Date(timeIntervalSince1970: 200_000)

        XCTAssertEqual(UsageFormatting.lastUpdatedDescription(nil, now: now), "Not captured yet")
        XCTAssertEqual(
            UsageFormatting.lastUpdatedDescription(now.addingTimeInterval(-30), now: now),
            "Updated just now"
        )
        XCTAssertEqual(
            UsageFormatting.lastUpdatedDescription(now.addingTimeInterval(-300), now: now),
            "Updated 5m ago"
        )
        XCTAssertEqual(
            UsageFormatting.lastUpdatedDescription(now.addingTimeInterval(-7_200), now: now),
            "Updated 2h ago"
        )
        XCTAssertEqual(
            UsageFormatting.lastUpdatedDescription(now.addingTimeInterval(-172_800), now: now),
            "Updated 2d ago"
        )
    }

    func testExtremeDatesNeverTrapFormatting() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let extremeFuture = Date(timeIntervalSince1970: 1e20)
        let extremePast = Date(timeIntervalSince1970: -1e20)

        XCTAssertEqual(
            UsageFormatting.resetDescription(resetsAt: extremeFuture, now: now),
            "Resets in 11574d 1h"
        )
        XCTAssertNil(
            UsageFormatting.resetDateDescription(resetsAt: extremeFuture, now: now)
        )
        XCTAssertEqual(
            UsageFormatting.lastUpdatedDescription(extremePast, now: now),
            "Updated 11574d ago"
        )
    }
}
