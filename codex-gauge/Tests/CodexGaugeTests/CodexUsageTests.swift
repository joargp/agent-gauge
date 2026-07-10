import Foundation
import XCTest
@testable import CodexGauge

final class CodexUsageTests: XCTestCase {
    func testRemainingPercentageIsClamped() {
        XCTAssertEqual(makeWindow(used: -8).remainingPercent, 100)
        XCTAssertEqual(makeWindow(used: 40.25).remainingPercent, 59.75)
        XCTAssertEqual(makeWindow(used: 140).remainingPercent, 0)
    }

    func testClassifiesWindowsByDurationWhenOrderIsSwapped() {
        let weekly = UsageWindow(usedPercent: 60, windowDurationMins: 10_080, resetsAt: nil)
        let fiveHour = UsageWindow(usedPercent: 20, windowDurationMins: 300, resetsAt: nil)
        let snapshot = CodexUsageSnapshot(
            primary: weekly,
            secondary: fiveHour,
            planType: "pro",
            fetchedAt: .now
        )

        XCTAssertEqual(snapshot.fiveHourWindow, fiveHour)
        XCTAssertEqual(snapshot.weeklyWindow, weekly)
    }

    private func makeWindow(used: Double) -> UsageWindow {
        UsageWindow(usedPercent: used, windowDurationMins: 300, resetsAt: nil)
    }
}
