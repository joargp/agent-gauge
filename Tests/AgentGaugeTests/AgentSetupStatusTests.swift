import ClaudeProvider
import CodexProvider
import Foundation
import XCTest
@testable import AgentGauge
import GaugeCore

final class AgentSetupStatusTests: XCTestCase {
    func testConnectedClaudeShowsVersion() {
        let status = AgentSetupStatus.claude(
            install: install(.installed(command: "/tmp/capture")),
            usage: snapshot(badge: "Claude Code 2.1.307")
        )

        XCTAssertEqual(status, AgentSetupStatus(tone: .ready, message: "Connected · Claude Code 2.1.307"))
    }

    func testIntegratedClaudeCountsAsConnected() {
        let status = AgentSetupStatus.claude(
            install: install(.integrated(command: "tee >(~/.claude/claude-gauge/capture) | other")),
            usage: nil
        )

        XCTAssertEqual(status, AgentSetupStatus(tone: .ready, message: "Connected"))
    }

    func testConnectedClaudeWithoutCaptureIsWaiting() {
        let status = AgentSetupStatus.claude(
            install: install(.installed(command: "/tmp/capture"), cacheFileExists: false),
            usage: nil
        )

        XCTAssertEqual(status.tone, .ready)
        XCTAssertEqual(status.message, "Connected · Waiting for the first capture")
        XCTAssertNil(status.action)
    }

    func testMissingStatusLineOffersConnect() {
        let status = AgentSetupStatus.claude(
            install: install(.missing, captureBinaryExists: false, cacheFileExists: false),
            usage: nil
        )

        XCTAssertEqual(
            status,
            AgentSetupStatus(tone: .attention, message: "Status line not connected", action: .connect)
        )
    }

    func testMissingHelperOffersConnect() {
        let status = AgentSetupStatus.claude(
            install: install(.installed(command: "/tmp/capture"), captureBinaryExists: false),
            usage: nil
        )

        XCTAssertEqual(status.tone, .attention)
        XCTAssertEqual(status.action, .connect)
    }

    func testForeignStatusLineShowsGuidanceWithoutConnect() {
        let foreign = install(.foreign(command: "my-statusline"))
        let status = AgentSetupStatus.claude(install: foreign, usage: nil)

        XCTAssertEqual(status.tone, .attention)
        XCTAssertEqual(status.message, foreign.guidanceMessage)
        XCTAssertNil(status.action)

        for state in [StatuslineInstallStatus.State.malformed, .unreadable] {
            XCTAssertNil(AgentSetupStatus.claude(install: install(state), usage: nil).action)
        }
    }

    func testSignedInCodexShowsPlan() {
        XCTAssertEqual(
            AgentSetupStatus.codex(.success(snapshot(badge: "Pro Lite"))),
            AgentSetupStatus(tone: .ready, message: "Signed in · Pro Lite")
        )
    }

    func testSignedOutCodexOffersLoginCommand() {
        let status = AgentSetupStatus.codex(.failure(CodexUsageError.notLoggedIn))

        XCTAssertEqual(status.tone, .attention)
        XCTAssertEqual(status.action, .copyLoginCommand)
        XCTAssertFalse(status.codexNotInstalled)
    }

    func testMissingCodexCLIIsNotInstalled() {
        let status = AgentSetupStatus.codex(.failure(CodexUsageError.executableNotFound))

        XCTAssertEqual(status, AgentSetupStatus(tone: .attention, message: "Codex CLI not found"))
        XCTAssertTrue(status.codexNotInstalled)
    }

    func testOtherCodexFailuresShowTheirDescription() {
        let status = AgentSetupStatus.codex(.failure(CodexUsageError.timedOut))

        XCTAssertEqual(status.message, CodexUsageError.timedOut.errorDescription)
        XCTAssertNil(status.action)
    }

    private func install(
        _ state: StatuslineInstallStatus.State,
        captureBinaryExists: Bool = true,
        cacheFileExists: Bool = true
    ) -> StatuslineInstallStatus {
        StatuslineInstallStatus(
            state: state,
            captureBinaryExists: captureBinaryExists,
            cacheFileExists: cacheFileExists
        )
    }

    private func snapshot(badge: String?) -> UsageSnapshot {
        UsageSnapshot(
            fiveHourWindow: nil,
            weeklyWindow: UsageWindow(usedPercent: 10, resetsAt: nil),
            badge: badge,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}
