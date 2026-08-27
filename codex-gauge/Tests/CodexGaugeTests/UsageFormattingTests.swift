import Foundation
import XCTest
@testable import CodexGauge

final class UsageFormattingTests: XCTestCase {
    func testResetDescriptionUsesCompactDurations() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            UsageFormatting.resetDescription(resetsAt: now.addingTimeInterval(90), now: now),
            "Resets in 1m"
        )
        XCTAssertEqual(
            UsageFormatting.resetDescription(resetsAt: now.addingTimeInterval(7_500), now: now),
            "Resets in 2h 5m"
        )
        XCTAssertEqual(
            UsageFormatting.resetDescription(resetsAt: now.addingTimeInterval(180_000), now: now),
            "Resets in 2d 2h"
        )
    }

    func testResetDateDescriptionIncludesDateAndTime() {
        let resetDate = Date(timeIntervalSince1970: 1_735_737_300)
        let description = UsageFormatting.resetDateDescription(
            resetsAt: resetDate,
            now: resetDate.addingTimeInterval(-60)
        )

        XCTAssertNotNil(description)
        XCTAssertTrue(description?.contains(":") == true)
        XCTAssertNil(UsageFormatting.resetDateDescription(resetsAt: nil))
    }

    func testPlanNameIsHumanReadable() {
        XCTAssertEqual(UsageFormatting.planDisplayName("chatgpt_pro"), "Chatgpt Pro")
    }
}
