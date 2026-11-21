import Foundation
import XCTest
@testable import ClaudeProvider
import GaugeCore

final class CaptureRunnerTests: XCTestCase {
    private func input(
        fiveHour: String = #"{"used_percentage":23.5,"resets_at":2000000000}"#,
        sevenDay: String = #"{"used_percentage":41.2,"resets_at":2000100000}"#
    ) -> Data {
        Data(
            #"{"model":{"display_name":"Sonnet 4.5"},"version":"2.1.250","rate_limits":{"five_hour":\#(fiveHour),"seven_day":\#(sevenDay)}}"#.utf8
        )
    }

    func testWritesCacheForFreshCapture() throws {
        let outcome = try CaptureRunner.run(
            input: input(),
            existingCache: nil,
            now: Date(timeIntervalSince1970: 1_738_425_010)
        )

        let cacheData = try XCTUnwrap(outcome.cacheData)
        let payload = try JSONDecoder().decode(UsageCachePayload.self, from: cacheData)
        XCTAssertEqual(payload.fiveHour?.usedPercentage, 23.5)
        XCTAssertEqual(payload.sevenDay?.usedPercentage, 41.2)
        XCTAssertEqual(payload.capturedAt, 1_738_425_010)
        XCTAssertEqual(payload.claudeCodeVersion, "2.1.250")
    }

    func testSkipsWriteWhenPayloadUnchangedWithinRoundingWindow() throws {
        let first = try CaptureRunner.run(
            input: input(),
            existingCache: nil,
            now: Date(timeIntervalSince1970: 1_738_425_012)
        )
        let cacheData = try XCTUnwrap(first.cacheData)

        let second = try CaptureRunner.run(
            input: input(),
            existingCache: cacheData,
            now: Date(timeIntervalSince1970: 1_738_425_018)
        )

        XCTAssertNil(second.cacheData, "timestamp rounds to the same 10s bucket, payload identical")
    }

    func testWritesAgainAfterRoundingWindowPasses() throws {
        let first = try CaptureRunner.run(
            input: input(),
            existingCache: nil,
            now: Date(timeIntervalSince1970: 1_738_425_012)
        )
        let cacheData = try XCTUnwrap(first.cacheData)

        let second = try CaptureRunner.run(
            input: input(),
            existingCache: cacheData,
            now: Date(timeIntervalSince1970: 1_738_425_022)
        )

        XCTAssertNotNil(second.cacheData)
    }

    func testEarlySessionWithoutRateLimitsNeverClobbersCache() throws {
        let earlyInput = Data(#"{"model":{"display_name":"Sonnet 4.5"}}"#.utf8)

        let outcome = try CaptureRunner.run(
            input: earlyInput,
            existingCache: nil,
            now: Date()
        )

        XCTAssertNil(outcome.cacheData)
        XCTAssertEqual(outcome.statusLineText, "Sonnet 4.5")
    }

    func testPresentButEmptyRateLimitsWritesEmptyFirstCache() throws {
        let input = Data(#"{"version":"2.1.250","rate_limits":{}}"#.utf8)

        let outcome = try CaptureRunner.run(
            input: input,
            existingCache: nil,
            now: Date(timeIntervalSince1970: 1_738_425_010)
        )

        let cacheData = try XCTUnwrap(outcome.cacheData)
        let payload = try JSONDecoder().decode(UsageCachePayload.self, from: cacheData)
        XCTAssertNil(payload.fiveHour)
        XCTAssertNil(payload.sevenDay)
    }

    func testMissingWindowsPreserveLastKnownRolloverMetadata() throws {
        let first = try CaptureRunner.run(
            input: input(),
            existingCache: nil,
            now: Date(timeIntervalSince1970: 1_738_425_010)
        )
        let existingCache = try XCTUnwrap(first.cacheData)
        let emptyUpdate = Data(#"{"version":"2.1.251","rate_limits":{}}"#.utf8)

        let second = try CaptureRunner.run(
            input: emptyUpdate,
            existingCache: existingCache,
            now: Date(timeIntervalSince1970: 2_000_200_000)
        )

        let cacheData = try XCTUnwrap(second.cacheData)
        let payload = try JSONDecoder().decode(UsageCachePayload.self, from: cacheData)
        XCTAssertEqual(payload.fiveHour?.resetsAt, 2_000_000_000)
        XCTAssertEqual(payload.sevenDay?.resetsAt, 2_000_100_000)
        XCTAssertEqual(payload.claudeCodeVersion, "2.1.251")
    }

    func testLaterCaptureCanReflectOutOfBandResetWithinSameWindow() throws {
        let first = try CaptureRunner.run(
            input: input(
                fiveHour: #"{"used_percentage":50,"resets_at":2000000000}"#
            ),
            existingCache: nil,
            now: Date(timeIntervalSince1970: 1_738_425_010)
        )
        let existingCache = try XCTUnwrap(first.cacheData)

        let resetSameWindow = try CaptureRunner.run(
            input: input(
                fiveHour: #"{"used_percentage":20,"resets_at":2000000000}"#
            ),
            existingCache: existingCache,
            now: Date(timeIntervalSince1970: 1_738_425_020)
        )
        let resetPayload = try JSONDecoder().decode(
            UsageCachePayload.self,
            from: XCTUnwrap(resetSameWindow.cacheData)
        )
        XCTAssertEqual(resetPayload.fiveHour?.usedPercentage, 20)

        let newerWindow = try CaptureRunner.run(
            input: input(
                fiveHour: #"{"used_percentage":5,"resets_at":2000100000}"#
            ),
            existingCache: existingCache,
            now: Date(timeIntervalSince1970: 1_738_425_030)
        )
        let newerPayload = try JSONDecoder().decode(
            UsageCachePayload.self,
            from: XCTUnwrap(newerWindow.cacheData)
        )
        XCTAssertEqual(newerPayload.fiveHour?.usedPercentage, 5)
        XCTAssertEqual(newerPayload.fiveHour?.resetsAt, 2_000_100_000)
    }

    func testDelayedCaptureCannotRegressSameUsageWindow() throws {
        let first = try CaptureRunner.run(
            input: input(
                fiveHour: #"{"used_percentage":50,"resets_at":2000000000}"#
            ),
            existingCache: nil,
            now: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let existingCache = try XCTUnwrap(first.cacheData)

        let delayed = try CaptureRunner.run(
            input: input(
                fiveHour: #"{"used_percentage":20,"resets_at":2000000000}"#
            ),
            existingCache: existingCache,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertNil(delayed.cacheData)
        let payload = try JSONDecoder().decode(UsageCachePayload.self, from: existingCache)
        XCTAssertEqual(payload.fiveHour?.usedPercentage, 50)
        XCTAssertEqual(payload.capturedAt, 1_800_000_100)
    }

    func testInvalidPreviousCacheIsDiscardedBeforeMerge() throws {
        let invalidCache = Data(
            #"{"captured_at":1800000000,"five_hour":{"used_percentage":99,"resets_at":1e20}}"#.utf8
        )
        let update = Data(#"{"version":"2.1.250","rate_limits":{}}"#.utf8)

        let outcome = try CaptureRunner.run(
            input: update,
            existingCache: invalidCache,
            now: Date(timeIntervalSince1970: 1_800_000_100)
        )

        let payload = try JSONDecoder().decode(
            UsageCachePayload.self,
            from: XCTUnwrap(outcome.cacheData)
        )
        XCTAssertNil(payload.fiveHour)
    }

    func testPartialCaptureDoesNotRefreshPreservedWeeklyReading() throws {
        let old = Data(#"{"captured_at":1800000000,"seven_day":{"used_percentage":92,"resets_at":2000100000}}"#.utf8)
        let now = Date(timeIntervalSince1970: 1_800_000_600)
        let outcome = try CaptureRunner.run(input: input(sevenDay: "null"), existingCache: old, now: now)
        let snapshot = try UsageCacheDecoder.decode(XCTUnwrap(outcome.cacheData))

        XCTAssertEqual(snapshot.fiveHourCapturedAt, now)
        XCTAssertEqual(snapshot.weeklyCapturedAt, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 8)
        XCTAssertEqual(snapshot.displayCapturedAt(now: now), snapshot.weeklyCapturedAt)
    }

    func testDelayedCaptureCannotRewindCapturedAt() throws {
        let first = try CaptureRunner.run(
            input: input(),
            existingCache: nil,
            now: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let existingCache = try XCTUnwrap(first.cacheData)

        let delayed = try CaptureRunner.run(
            input: input(
                fiveHour: #"{"used_percentage":30,"resets_at":2000000000}"#
            ),
            existingCache: existingCache,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertNil(delayed.cacheData)
        let payload = try JSONDecoder().decode(UsageCachePayload.self, from: existingCache)
        XCTAssertEqual(payload.capturedAt, 1_800_000_100)
    }

    func testRolledOverWindowIsWrittenButNotDisplayed() throws {
        // resets_at in the past: still cached (so the app can show the
        // rolled-over state) but omitted from the status line.
        let past = Int(Date().timeIntervalSince1970) - 100
        let outcome = try CaptureRunner.run(
            input: input(fiveHour: #"{"used_percentage":23.5,"resets_at":\#(past)}"#),
            existingCache: nil,
            now: Date()
        )

        let cacheData = try XCTUnwrap(outcome.cacheData)
        let payload = try JSONDecoder().decode(UsageCachePayload.self, from: cacheData)
        XCTAssertEqual(payload.fiveHour?.usedPercentage, 23.5)
        XCTAssertFalse(outcome.statusLineText.contains("5h"))
        XCTAssertTrue(outcome.statusLineText.contains("W"))
    }

    func testInvalidInputThrows() {
        XCTAssertThrowsError(
            try CaptureRunner.run(input: Data("nope".utf8), existingCache: nil)
        ) { error in
            XCTAssertEqual(error as? CaptureRunnerError, .invalidInput)
        }
    }

    func testStatusLineTextColorsLowRemaining() throws {
        let critical = try CaptureRunner.run(
            input: input(fiveHour: #"{"used_percentage":95,"resets_at":2000000000}"#),
            existingCache: nil,
            now: Date()
        )
        XCTAssertTrue(critical.statusLineText.contains("\u{1B}[31m"))

        let warning = try CaptureRunner.run(
            input: input(fiveHour: #"{"used_percentage":80,"resets_at":2000000000}"#),
            existingCache: nil,
            now: Date()
        )
        XCTAssertTrue(warning.statusLineText.contains("\u{1B}[33m"))

        let healthy = try CaptureRunner.run(
            input: input(),
            existingCache: nil,
            now: Date()
        )
        XCTAssertFalse(healthy.statusLineText.contains("\u{1B}"))
    }

    func testStatusLineTextIncludesModelAndBothWindows() throws {
        let outcome = try CaptureRunner.run(input: input(), existingCache: nil, now: Date())

        XCTAssertEqual(
            outcome.statusLineText
                .replacingOccurrences(of: "\u{1B}[0m", with: "")
                .replacingOccurrences(of: "\u{1B}[33m", with: "")
                .replacingOccurrences(of: "\u{1B}[31m", with: ""),
            "Sonnet 4.5 · 5h 77% · W 59%"
        )
    }

    // MARK: - Claude profile provenance

    func testRecordsOneProfileForTheSnapshot() throws {
        let outcome = try CaptureRunner.run(
            input: input(), existingCache: nil,
            now: Date(timeIntervalSince1970: 1_800_000_000), configDir: "/Users/test/.claude"
        )
        let payload = try UsageCacheDecoder.decodePayload(XCTUnwrap(outcome.cacheData))
        XCTAssertEqual(payload.configDir, "/Users/test/.claude")
    }

    func testOtherProfileWindowIsNotPreservedBesideThisCapture() throws {
        let other = try CaptureRunner.run(
            input: input(), existingCache: nil,
            now: Date(timeIntervalSince1970: 1_800_000_000), configDir: "/Users/test/.claude-work"
        )
        let outcome = try CaptureRunner.run(
            input: input(sevenDay: "null"), existingCache: other.cacheData,
            now: Date(timeIntervalSince1970: 1_800_000_600), configDir: "/Users/test/.claude"
        )
        let payload = try UsageCacheDecoder.decodePayload(XCTUnwrap(outcome.cacheData))
        XCTAssertEqual(payload.configDir, "/Users/test/.claude")
        XCTAssertNil(payload.sevenDay, "Another login's weekly window must not sit beside this 5-hour window")
    }

    func testCanonicallyEquivalentProfileIDsDoNotSharePreservedWindows() throws {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for key in ["CLAUDE_CONFIG_DIR", "CLAUDE_SECURESTORAGE_CONFIG_DIR"] {
            let firstID = ClaudeConfigProfile.identifier(environment: [key: "/tmp/caf\u{e9}"], homeDirectory: home)
            let secondID = ClaudeConfigProfile.identifier(environment: [key: "/tmp/cafe\u{301}"], homeDirectory: home)
            XCTAssertEqual(firstID, secondID, "Swift String equality is not byte equality")
            XCTAssertNotEqual(Data(firstID.utf8), Data(secondID.utf8))

            let first = try CaptureRunner.run(input: input(), existingCache: nil, now: start, configDir: firstID)
            let partial = try CaptureRunner.run(
                input: input(sevenDay: "null"), existingCache: first.cacheData,
                now: start.addingTimeInterval(10), configDir: secondID
            )
            let payload = try UsageCacheDecoder.decodePayload(XCTUnwrap(partial.cacheData))
            XCTAssertEqual(Data(try XCTUnwrap(payload.configDir).utf8), Data(secondID.utf8))
            XCTAssertNotNil(payload.fiveHour)
            XCTAssertNil(payload.sevenDay, "Profile ID bytes must match before preserving a window")
        }
    }

    func testOAuthCapturesDoNotMergeAcrossLogins() throws {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let keychainEnvironment = [
            "CLAUDE_CONFIG_DIR": "/Users/test/.claude-work",
            "CLAUDE_SECURESTORAGE_CONFIG_DIR": "/Users/test/keychain"
        ]
        let keychain = ClaudeConfigProfile.identifier(environment: keychainEnvironment, homeDirectory: home)
        let oauth = ["test-token-a", "test-token-b", ""].map { fixture in
            ClaudeConfigProfile.identifier(
                environment: keychainEnvironment.merging(["CLAUDE_CODE_OAUTH_TOKEN": fixture]) { _, new in new },
                homeDirectory: home
            )
        }
        XCTAssertTrue(oauth.allSatisfy { $0 == "explicit-oauth" }, "Only presence is recorded")
        XCTAssertNotEqual(keychain, oauth[0])

        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for (previous, next) in [(keychain, oauth[0]), (oauth[0], oauth[1]), (oauth[1], keychain)] {
            let first = try CaptureRunner.run(input: input(), existingCache: nil, now: start, configDir: previous)
            let latest = try CaptureRunner.run(
                input: input(sevenDay: "null"), existingCache: first.cacheData,
                now: start.addingTimeInterval(10), configDir: next
            )
            let payload = try UsageCacheDecoder.decodePayload(XCTUnwrap(latest.cacheData))
            XCTAssertEqual(payload.configDir, next)
            XCTAssertEqual(payload.fiveHour?.usedPercentage, 23.5)
            XCTAssertNil(payload.sevenDay, "Never borrow a window even when both captures carry the OAuth marker")
        }
    }

    func testLaterCaptureFromOtherProfileWinsDespiteEarlierReset() throws {
        let other = try CaptureRunner.run(
            input: input(sevenDay: #"{"used_percentage":10,"resets_at":2000500000}"#), existingCache: nil,
            now: Date(timeIntervalSince1970: 1_800_000_000), configDir: "/Users/test/.claude-work"
        )
        let outcome = try CaptureRunner.run(
            input: input(sevenDay: #"{"used_percentage":70,"resets_at":2000100000}"#), existingCache: other.cacheData,
            now: Date(timeIntervalSince1970: 1_800_000_600), configDir: "/Users/test/.claude"
        )
        let payload = try UsageCacheDecoder.decodePayload(XCTUnwrap(outcome.cacheData))
        XCTAssertEqual(payload.sevenDay?.usedPercentage, 70)
        XCTAssertEqual(payload.configDir, "/Users/test/.claude")
    }

    func testFirstProfiledCaptureDoesNotInheritLegacyWindows() throws {
        let legacy = Data(#"{"captured_at":1800000000,"five_hour":{"used_percentage":5,"resets_at":2000000000},"seven_day":{"used_percentage":92,"resets_at":2000100000}}"#.utf8)
        let outcome = try CaptureRunner.run(
            input: input(sevenDay: "null"), existingCache: legacy,
            now: Date(timeIntervalSince1970: 1_800_000_600), configDir: "/Users/test/.claude"
        )
        let payload = try UsageCacheDecoder.decodePayload(XCTUnwrap(outcome.cacheData))
        XCTAssertEqual(payload.configDir, "/Users/test/.claude")
        XCTAssertNil(payload.sevenDay)
    }

    func testDelayedForeignCaptureCannotReplaceOnlyTheOlderWindow() throws {
        let profile = "/Users/test/.claude"
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try CaptureRunner.run(input: input(), existingCache: nil, now: start, configDir: profile)
        let partial = try CaptureRunner.run(
            input: input(sevenDay: "null"), existingCache: first.cacheData,
            now: start.addingTimeInterval(20), configDir: profile
        )
        let delayed = try CaptureRunner.run(
            input: input(), existingCache: partial.cacheData,
            now: start.addingTimeInterval(10), configDir: "/Users/test/.claude-work"
        )
        XCTAssertNil(delayed.cacheData)
        XCTAssertFalse(delayed.statusLineText.isEmpty)
    }

    func testProfileIdentifierFollowsClaudeConfigDir() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        func identifier(_ value: String?, cwd: String = "/Users/test/project") -> String {
            ClaudeConfigProfile.identifier(
                environment: value.map { ["CLAUDE_CONFIG_DIR": $0] } ?? [:],
                homeDirectory: home,
                currentDirectory: cwd
            )
        }
        XCTAssertEqual(identifier(nil), "/Users/test/.claude")
        // Explicit values are kept literally: Claude Code's Keychain item
        // depends on the exact string.
        XCTAssertEqual(identifier("/Users/test/.claude"), "override:/Users/test/.claude")
        XCTAssertEqual(identifier("/Users/test/.claude/"), "override:/Users/test/.claude/")
        XCTAssertEqual(identifier("/Users/test/work/../.claude-work"), "override:/Users/test/work/../.claude-work")
    }

    func testRelativeProfileIsKeptApartAndNeverMatchesTheApp() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        func identifier(_ value: String, cwd: String) -> String {
            ClaudeConfigProfile.identifier(
                environment: ["CLAUDE_CONFIG_DIR": value], homeDirectory: home, currentDirectory: cwd
            )
        }
        let relative = identifier("profile", cwd: "/Users/test/a")
        XCTAssertEqual(relative, identifier("profile", cwd: "/Users/test/a"))
        XCTAssertNotEqual(relative, identifier("profile", cwd: "/Users/test/b"), "Another folder")
        XCTAssertNotEqual(relative, identifier("./profile", cwd: "/Users/test/a"), "Another Keychain item")
        XCTAssertNotEqual(identifier("", cwd: "/Users/test"), identifier(" ", cwd: "/Users/test"))
        XCTAssertNotEqual(identifier("", cwd: "/Users/test"), "/Users/test/.claude")
        for value in ["profile", "", " ", "~/.claude"] {
            XCTAssertTrue(identifier(value, cwd: "/Users/test/.claude").hasPrefix("relative:"))
        }
    }
}
