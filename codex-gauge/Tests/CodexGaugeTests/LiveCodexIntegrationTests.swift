import Foundation
import XCTest
@testable import CodexGauge

final class LiveCodexIntegrationTests: XCTestCase {
    func testReadsUsageFromLoggedInLocalCodex() async throws {
        guard ProcessInfo.processInfo.environment["CODEX_GAUGE_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set CODEX_GAUGE_LIVE_TEST=1 to query the locally logged-in Codex account.")
        }

        let usage = try await CodexAppServerClient().fetchUsage()

        XCTAssertNotNil(usage.fiveHourWindow)
        XCTAssertNotNil(usage.weeklyWindow)
        XCTAssertTrue((0...100).contains(usage.fiveHourWindow?.remainingPercent ?? -1))
        XCTAssertTrue((0...100).contains(usage.weeklyWindow?.remainingPercent ?? -1))
    }
}
