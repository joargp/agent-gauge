import Foundation
import XCTest
@testable import ClaudeProvider
import GaugeCore

final class LiveClaudeUsageTests: XCTestCase {
    func testReadsFableFromLocalClaudeCLI() async throws {
        guard ProcessInfo.processInfo.environment["CLAUDE_GAUGE_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set CLAUDE_GAUGE_LIVE_TEST=1 to run the local Claude CLI.")
        }

        let outcome = await ClaudeUsageCommand().fetchUsage()

        guard case .reading(let weekly, let fable?) = outcome else {
            return XCTFail("Expected weekly and Fable limits, got \(outcome)")
        }
        XCTAssertTrue((0...100).contains(weekly.remainingPercent))
        XCTAssertNotNil(weekly.resetsAt)
        print("LIVE Fable: name=\(fable.name) used=\(fable.window.usedPercent) resetsAt=\(String(describing: fable.window.resetsAt))")
        XCTAssertTrue((0...100).contains(fable.window.remainingPercent))
        XCTAssertNotNil(fable.window.resetsAt)
    }
}
