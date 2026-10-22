import Foundation
import XCTest
@testable import CodexProvider
import GaugeCore

final class LiveCodexIntegrationTests: XCTestCase {
    func testReadsUsageFromLoggedInLocalCodex() async throws {
        guard ProcessInfo.processInfo.environment["CODEX_GAUGE_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set CODEX_GAUGE_LIVE_TEST=1 to query the locally logged-in Codex account.")
        }

        let usage = try await CodexAppServerClient().readUsage()

        // Some plans only have a weekly window.
        XCTAssertNotNil(usage.weeklyWindow)
        for window in [usage.fiveHourWindow, usage.weeklyWindow].compactMap({ $0 }) {
            XCTAssertTrue((0...100).contains(window.remainingPercent))
        }
    }
}
