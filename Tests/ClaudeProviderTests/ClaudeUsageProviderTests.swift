import Foundation
import XCTest
@testable import ClaudeProvider
import GaugeCore

final class ClaudeUsageProviderTests: XCTestCase {
    private static let profile = "/Users/test/.claude"
    private static let otherProfile = "/Users/test/.claude-work"

    private actor ScriptedCLI {
        var outcomes: [SubLimitReader.Outcome]

        init(_ outcomes: [SubLimitReader.Outcome]) { self.outcomes = outcomes }

        func fetch() -> SubLimitReader.Outcome { outcomes.removeFirst() }
    }

    func testFailedVerificationFallsBackToNewerStatuslineCorrection() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let locations = CacheLocations(homeDirectory: dir)
        try FileManager.default.createDirectory(at: locations.installDirectory, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let reset = now.addingTimeInterval(3_600)
        let old = UsageWindow(usedPercent: 92, resetsAt: reset)
        let cli = ScriptedCLI([.reading(weekly: old, fable: nil), .failed])
        let clock = TestClock(now)
        let reader = SubLimitReader(configProfile: Self.profile, fetch: { await cli.fetch() }, now: { clock.now })
        let provider = ClaudeUsageProvider(locations: locations, subLimitReader: reader)

        func writeCache(used: Int, capturedAt: Date) throws {
            let cache = Data(#"{"captured_at":\#(capturedAt.timeIntervalSince1970),"config_dir":"\#(Self.profile)","seven_day":{"used_percentage":\#(used),"resets_at":\#(reset.timeIntervalSince1970)}}"#.utf8)
            try cache.write(to: locations.cacheFile, options: .atomic)
        }

        try writeCache(used: 92, capturedAt: now)
        let initial = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(initial.weeklyWindow?.remainingPercent, 8)

        clock.advance(61)
        try writeCache(used: 54, capturedAt: clock.now)
        let corrected = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(corrected.weeklyWindow?.remainingPercent, 46)
        XCTAssertEqual(corrected.weeklyCapturedAt, clock.now)
    }

    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var date: Date

        init(_ date: Date) { self.date = date }
        var now: Date { lock.withLock { date } }
        func advance(_ seconds: TimeInterval) { lock.withLock { date.addTimeInterval(seconds) } }
    }

    func testVerifiedWeeklyCorrectionWinsOverStatuslineWithoutChangingFiveHourAge() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let locations = CacheLocations(homeDirectory: dir)
        try FileManager.default.createDirectory(at: locations.installDirectory, withIntermediateDirectories: true)

        let fiveHourAt = Date(timeIntervalSince1970: 1_800_000_000)
        let checkedAt = fiveHourAt.addingTimeInterval(600)
        let reset = fiveHourAt.addingTimeInterval(3_600)
        let verified = UsageWindow(usedPercent: 54, resetsAt: reset)
        let reader = SubLimitReader(configProfile: Self.profile, fetch: { .reading(weekly: verified, fable: nil) }, now: { checkedAt })
        let provider = ClaudeUsageProvider(locations: locations, subLimitReader: reader)
        let cache = Data(#"{"captured_at":1800000600,"config_dir":"/Users/test/.claude","five_hour":{"used_percentage":4,"resets_at":1800003600,"captured_at":1800000000},"seven_day":{"used_percentage":92,"resets_at":1800003600}}"#.utf8)
        try cache.write(to: locations.cacheFile)

        let snapshot = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 46)
        XCTAssertEqual(snapshot.weeklyCapturedAt, checkedAt)
        XCTAssertEqual(snapshot.fiveHourWindow?.remainingPercent, 96)
        XCTAssertEqual(snapshot.displayCapturedAt(now: checkedAt), fiveHourAt)

        let background = try await provider.readUsage()
        XCTAssertEqual(background.weeklyWindow, verified)
    }

    func testFallsBackToStatuslineWhenCLIIsUnavailable() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let locations = CacheLocations(homeDirectory: dir)
        try FileManager.default.createDirectory(at: locations.installDirectory, withIntermediateDirectories: true)
        let cache = Data(#"{"captured_at":1800000600,"seven_day":{"used_percentage":92,"resets_at":1800003600}}"#.utf8)
        try cache.write(to: locations.cacheFile)
        let reader = SubLimitReader(configProfile: Self.profile, fetch: { .failed }, now: { Date(timeIntervalSince1970: 1_800_000_610) })
        let provider = ClaudeUsageProvider(locations: locations, subLimitReader: reader)

        let snapshot = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 8)
        XCTAssertEqual(snapshot.weeklyCapturedAt, Date(timeIntervalSince1970: 1_800_000_600))
    }

    // MARK: - Rejected redraws (P1)

    func testFailedCheckKeepsVerifiedValueWhenIdleSessionRedrawsRejectedReading() async throws {
        let locations = try makeLocations()
        defer { try? FileManager.default.removeItem(at: locations.homeDirectory) }
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let reset = now.addingTimeInterval(3_600)
        let verified = UsageWindow(usedPercent: 92, resetsAt: reset)
        let cli = ScriptedCLI([.reading(weekly: verified, fable: nil), .failed, .failed])
        let clock = TestClock(now)
        let reader = SubLimitReader(configProfile: Self.profile, fetch: { await cli.fetch() }, now: { clock.now })
        let provider = ClaudeUsageProvider(locations: locations, subLimitReader: reader)

        // An idle session still reports 46% left; /usage says 8%.
        try writeCache(locations, weekly: (54, reset), capturedAt: now, profile: Self.profile)
        let initial = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(initial.weeklyWindow?.remainingPercent, 8)

        // The same session redraws the same reading later; /usage then fails.
        clock.advance(61)
        try writeCache(locations, weekly: (54, reset), capturedAt: clock.now, profile: Self.profile)
        let redrawn = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(redrawn.weeklyWindow?.remainingPercent, 8)
        XCTAssertEqual(redrawn.weeklyCapturedAt, now)

        // A genuinely changed, newer reading still wins while /usage fails.
        clock.advance(61)
        try writeCache(locations, weekly: (55, reset), capturedAt: clock.now, profile: Self.profile)
        let changed = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(changed.weeklyWindow?.remainingPercent, 45)
        XCTAssertEqual(changed.weeklyCapturedAt, clock.now)
    }

    // MARK: - Profile provenance (P2)

    func testCanonicallyEquivalentProfileIDsDoNotMatchOrShareFable() async throws {
        let locations = try makeLocations()
        defer { try? FileManager.default.removeItem(at: locations.homeDirectory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = now.addingTimeInterval(3_600)
        let verified = UsageWindow(usedPercent: 92, resetsAt: reset)
        let fable = SubLimit(name: "Fable", window: UsageWindow(usedPercent: 30, resetsAt: reset))
        let appProfile = "override:/tmp/caf\u{e9}"
        let otherProfile = "override:/tmp/cafe\u{301}"
        XCTAssertEqual(appProfile, otherProfile)
        XCTAssertNotEqual(Data(appProfile.utf8), Data(otherProfile.utf8))
        let reader = SubLimitReader(configProfile: appProfile, fetch: { .reading(weekly: verified, fable: fable) }, now: { now })
        let provider = ClaudeUsageProvider(locations: locations, subLimitReader: reader)

        try writeCache(locations, weekly: (54, reset), capturedAt: now, profile: otherProfile)
        let other = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(other.weeklyWindow?.usedPercent, 54)
        XCTAssertNil(other.subLimit)

        try writeCache(locations, weekly: (54, reset), capturedAt: now, profile: appProfile)
        let own = try await provider.readUsage()
        XCTAssertEqual(own.weeklyWindow, verified)
        XCTAssertEqual(own.subLimit, fable)
    }

    func testOtherProfileCacheIsNotMixedWithCLIReading() async throws {
        let locations = try makeLocations()
        defer { try? FileManager.default.removeItem(at: locations.homeDirectory) }
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let reset = now.addingTimeInterval(3_600)
        let fable = SubLimit(name: "Fable", window: UsageWindow(usedPercent: 30, resetsAt: reset))
        let cli = Counter(.reading(weekly: UsageWindow(usedPercent: 92, resetsAt: reset), fable: fable))
        let clock = TestClock(now)
        let reader = SubLimitReader(configProfile: Self.profile, fetch: { await cli.fetch() }, now: { clock.now })
        let provider = ClaudeUsageProvider(locations: locations, subLimitReader: reader)

        try writeCache(
            locations,
            fiveHour: (10, reset),
            weekly: (54, reset),
            capturedAt: now,
            profile: Self.otherProfile
        )
        let snapshot = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(snapshot.fiveHourWindow?.remainingPercent, 90)
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 46)
        XCTAssertEqual(snapshot.weeklyCapturedAt, now)
        XCTAssertNil(snapshot.subLimit, "The Fable limit belongs to another login")

        // Another login's reading is not a disagreement to re-verify each minute.
        clock.advance(61)
        try writeCache(
            locations,
            fiveHour: (10, reset),
            weekly: (54, reset),
            capturedAt: clock.now,
            profile: Self.otherProfile
        )
        _ = try await provider.readUsage()
        try await Task.sleep(for: .milliseconds(50))
        let calls = await cli.calls
        XCTAssertEqual(calls, 1)
    }

    func testLegacyCacheWithoutProfileSkipsWeeklyOverrideButKeepsFable() async throws {
        let locations = try makeLocations()
        defer { try? FileManager.default.removeItem(at: locations.homeDirectory) }
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let reset = now.addingTimeInterval(3_600)
        let fable = SubLimit(name: "Fable", window: UsageWindow(usedPercent: 30, resetsAt: reset))
        let cli = Counter(.reading(weekly: UsageWindow(usedPercent: 92, resetsAt: reset), fable: fable))
        let reader = SubLimitReader(configProfile: Self.profile, fetch: { await cli.fetch() }, now: { now })
        let provider = ClaudeUsageProvider(locations: locations, subLimitReader: reader)

        // Written by a helper that predates per-window timestamps and profile metadata.
        let legacy = Data(#"{"captured_at":\#(now.timeIntervalSince1970),"five_hour":{"used_percentage":10,"resets_at":\#(reset.timeIntervalSince1970)},"seven_day":{"used_percentage":54,"resets_at":\#(reset.timeIntervalSince1970)}}"#.utf8)
        try legacy.write(to: locations.cacheFile, options: .atomic)
        let snapshot = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 46)
        XCTAssertEqual(snapshot.weeklyCapturedAt, now)
        XCTAssertEqual(snapshot.subLimit, fable)

        // Once the updated helper records the profile, verification applies.
        try writeCache(locations, fiveHour: (10, reset), weekly: (54, reset), capturedAt: now, profile: Self.profile)
        let associated = try await provider.readUsage()
        XCTAssertEqual(associated.weeklyWindow?.remainingPercent, 8)
    }

    /// Same `CLAUDE_CONFIG_DIR`, different Keychain logins.
    func testSecureStorageDirKeepsKeychainLoginsApart() async throws {
        let locations = try makeLocations()
        defer { try? FileManager.default.removeItem(at: locations.homeDirectory) }
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        func environment(_ storage: String) -> [String: String] {
            ["CLAUDE_CONFIG_DIR": "/Users/test/.claude-work", "CLAUDE_SECURESTORAGE_CONFIG_DIR": storage]
        }
        let appProfile = try XCTUnwrap(
            ClaudeExecutableResolver(environment: environment("/Users/test/keychain-a"), homeDirectory: home).configProfile
        )
        func helperProfile(_ storage: String) -> String {
            ClaudeConfigProfile.identifier(
                environment: environment(storage), homeDirectory: home, currentDirectory: "/Users/test/project"
            )
        }
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let reset = now.addingTimeInterval(3_600)
        let fable = SubLimit(name: "Fable", window: UsageWindow(usedPercent: 30, resetsAt: reset))
        let cli = Counter(.reading(weekly: UsageWindow(usedPercent: 92, resetsAt: reset), fable: fable))
        let clock = TestClock(now)
        let reader = SubLimitReader(configProfile: appProfile, fetch: { await cli.fetch() }, now: { clock.now })
        let provider = ClaudeUsageProvider(locations: locations, subLimitReader: reader)

        try writeCache(locations, weekly: (54, reset), capturedAt: now, profile: helperProfile("/Users/test/keychain-b"))
        let other = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(other.weeklyWindow?.remainingPercent, 46, "Another login's reading is not replaced")
        XCTAssertNil(other.subLimit, "The Fable limit belongs to another login")

        clock.advance(61)
        try writeCache(locations, weekly: (54, reset), capturedAt: clock.now, profile: helperProfile("/Users/test/keychain-a"))
        let same = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(same.weeklyWindow?.remainingPercent, 8)
        XCTAssertEqual(same.subLimit, fable)
    }

    func testRelativeSecureStorageDirIsNeverCombined() async throws {
        let locations = try makeLocations()
        defer { try? FileManager.default.removeItem(at: locations.homeDirectory) }
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let environment = ["CLAUDE_SECURESTORAGE_CONFIG_DIR": "keychain"]
        let resolver = ClaudeExecutableResolver(environment: environment, homeDirectory: home)
        XCTAssertNil(resolver.configProfile)
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let reset = now.addingTimeInterval(3_600)
        let cli = Counter(.reading(weekly: UsageWindow(usedPercent: 92, resetsAt: reset), fable: nil))
        let reader = SubLimitReader(configProfile: resolver.configProfile, fetch: { await cli.fetch() }, now: { now })
        let provider = ClaudeUsageProvider(locations: locations, subLimitReader: reader)

        let helper = ClaudeConfigProfile.identifier(
            environment: environment, homeDirectory: home, currentDirectory: "/Users/test"
        )
        try writeCache(locations, weekly: (54, reset), capturedAt: now, profile: helper)
        let snapshot = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(snapshot.weeklyWindow?.remainingPercent, 46)
        XCTAssertEqual(snapshot.weeklyCapturedAt, now)
    }

    func testOAuthCaptureCannotBeVerifiedWithKeychainUsage() async throws {
        let locations = try makeLocations()
        defer { try? FileManager.default.removeItem(at: locations.homeDirectory) }
        let home = locations.homeDirectory
        let appProfile = try XCTUnwrap(ClaudeExecutableResolver(environment: [:], homeDirectory: home).configProfile)
        let oauthCapture = ClaudeConfigProfile.identifier(
            environment: ["CLAUDE_CODE_OAUTH_TOKEN": "test-token"], homeDirectory: home
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = now.addingTimeInterval(3_600)
        let checked = UsageWindow(usedPercent: 92, resetsAt: reset)
        let fable = SubLimit(name: "Fable", window: checked)
        let cli = ScriptedCLI([.reading(weekly: checked, fable: fable), .absent])
        let clock = TestClock(now)
        let reader = SubLimitReader(configProfile: appProfile, fetch: { await cli.fetch() }, now: { clock.now })
        let provider = ClaudeUsageProvider(locations: locations, subLimitReader: reader)

        try writeCache(locations, weekly: (54, reset), capturedAt: now, profile: oauthCapture)
        let oauth = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(oauth.weeklyWindow?.usedPercent, 54)
        XCTAssertNil(oauth.subLimit)

        // A check for the normal login must not have rejected the token
        // login's reading, even if the normal login reports the same value.
        clock.advance(61)
        try writeCache(locations, weekly: (54, reset), capturedAt: clock.now, profile: appProfile)
        let keychain = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(keychain.weeklyWindow?.usedPercent, 54)
        XCTAssertFalse(keychain.weeklyUnavailable)
    }

    // MARK: - Rejections without a trustworthy weekly value

    func testExpiredYearlessRowKeepsNewWeekFallbackAndPriorRejection() async throws {
        let locations = try makeLocations()
        defer { try? FileManager.default.removeItem(at: locations.homeDirectory) }
        let iso = ISO8601DateFormatter()
        let nov18 = try XCTUnwrap(iso.date(from: "2026-11-18T12:00:00Z"))
        let nov20 = try XCTUnwrap(iso.date(from: "2026-11-20T12:00:00Z"))
        let nextReset = try XCTUnwrap(iso.date(from: "2026-11-25T20:00:00Z"))
        let clock = TestClock(nov18)
        let reader = SubLimitReader(configProfile: Self.profile, fetch: {
            let now = clock.now
            let text = now < nov20
                ? "Current week (all models): 55% used · resets Nov 18 at 8pm (UTC)"
                : """
                Current week (all models): 92% used · resets Nov 18 at 8pm (UTC)
                Current week (Fable): 30% used · resets Nov 25 at 8pm (UTC)
                """
            return ClaudeUsageCommand.parseUsage(text, now: now)
        }, now: { clock.now })
        let provider = ClaudeUsageProvider(locations: locations, subLimitReader: reader)

        // A later row with 92% would clear this rejection if treated as current.
        let resetless = UsageWindow(usedPercent: 92, resetsAt: nil)
        let initial = await reader.currentReading(userInitiated: true, capturedAt: nov18, statuslineWeekly: resetless)
        XCTAssertTrue(initial.rejects(resetless))

        clock.advance(nov20.timeIntervalSince(nov18))
        let fallback = UsageWindow(usedPercent: 4, resetsAt: nextReset)
        try writeCache(locations, weekly: (4, nextReset), capturedAt: nov20, profile: Self.profile)
        let snapshot = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(snapshot.weeklyWindow, fallback)
        XCTAssertEqual(snapshot.weeklyCapturedAt, nov20)
        XCTAssertFalse(snapshot.weeklyUnavailable)
        XCTAssertEqual(snapshot.subLimit, SubLimit(name: "Fable", window: UsageWindow(usedPercent: 30, resetsAt: nextReset)))

        let latest = await reader.reconcile(statuslineWeekly: nil, capturedAt: nil)
        XCTAssertTrue(latest.rejects(resetless), "The expired row cannot clear a prior rejection")
        XCTAssertFalse(latest.rejects(fallback), "The expired row cannot reject the active fallback")
    }

    func testWeeklyRowExpiredByCompletionLeavesActiveNewWeekFallbackAndFable() async throws {
        let locations = try makeLocations()
        defer { try? FileManager.default.removeItem(at: locations.homeDirectory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = TestClock(now)
        let ending = UsageWindow(usedPercent: 92, resetsAt: now.addingTimeInterval(5))
        let nextReset = now.addingTimeInterval(604_800)
        let fable = SubLimit(name: "Fable", window: UsageWindow(usedPercent: 30, resetsAt: nextReset))
        let reader = SubLimitReader(configProfile: Self.profile, fetch: {
            clock.advance(5)
            return .reading(weekly: ending, fable: fable)
        }, now: { clock.now })
        let provider = ClaudeUsageProvider(locations: locations, subLimitReader: reader)

        // The active fallback was already in the cache before the check,
        // but `/usage` returned a row with the old reset time.
        try writeCache(locations, weekly: (4, nextReset), capturedAt: now, profile: Self.profile)
        let snapshot = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(snapshot.weeklyWindow, UsageWindow(usedPercent: 4, resetsAt: nextReset))
        XCTAssertFalse(snapshot.weeklyUnavailable)
        XCTAssertEqual(snapshot.weeklyCapturedAt, now)
        XCTAssertEqual(snapshot.subLimit, fable)
    }

    func testRejectedRedrawIsUnavailableAfterLongCLIOutage() async throws {
        let locations = try makeLocations()
        defer { try? FileManager.default.removeItem(at: locations.homeDirectory) }
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let reset = now.addingTimeInterval(86_400)
        let cli = ScriptedCLI([.reading(weekly: UsageWindow(usedPercent: 92, resetsAt: reset), fable: nil)]
            + Array(repeating: .failed, count: 4))
        let clock = TestClock(now)
        let reader = SubLimitReader(configProfile: Self.profile, fetch: { await cli.fetch() }, now: { clock.now })
        let provider = ClaudeUsageProvider(locations: locations, subLimitReader: reader)

        try writeCache(locations, weekly: (54, reset), capturedAt: now, profile: Self.profile)
        let initial = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(initial.weeklyWindow?.remainingPercent, 8)

        // Half an hour of failures retires the verified value. The idle
        // session's redraw is still known to be wrong.
        clock.advance(61)
        _ = try await provider.readUsage(userInitiated: true)
        clock.advance(SubLimitReader.staleAfterFailures)
        try writeCache(locations, fiveHour: (20, reset), weekly: (54, reset), capturedAt: clock.now, profile: Self.profile)
        let outage = try await provider.readUsage(userInitiated: true)
        XCTAssertNil(outage.weeklyWindow)
        XCTAssertTrue(outage.weeklyUnavailable)
        XCTAssertEqual(outage.weeklyState(now: clock.now), .rolledOver)
        XCTAssertEqual(outage.fiveHourWindow?.remainingPercent, 80)
        XCTAssertEqual(outage.displayCapturedAt(now: clock.now), clock.now, "The 5-hour reading keeps its own age")

        // A changed reading in the same window is new information.
        clock.advance(61)
        try writeCache(locations, weekly: (55, reset), capturedAt: clock.now, profile: Self.profile)
        let changed = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(changed.weeklyWindow?.remainingPercent, 45)
        XCTAssertFalse(changed.weeklyUnavailable)
    }

    func testRejectedReadingIsNotAFallbackOnceTheVerifiedWeeklyExpires() async throws {
        let locations = try makeLocations()
        defer { try? FileManager.default.removeItem(at: locations.homeDirectory) }
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let ending = now.addingTimeInterval(100)
        let later = now.addingTimeInterval(86_400)
        let fable = SubLimit(name: "Fable", window: UsageWindow(usedPercent: 30, resetsAt: later))
        let cli = ScriptedCLI([.reading(weekly: UsageWindow(usedPercent: 92, resetsAt: ending), fable: fable), .failed])
        let clock = TestClock(now)
        let reader = SubLimitReader(configProfile: Self.profile, fetch: { await cli.fetch() }, now: { clock.now })
        let provider = ClaudeUsageProvider(locations: locations, subLimitReader: reader)

        try writeCache(locations, weekly: (40, later), capturedAt: now, profile: Self.profile)
        let initial = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(initial.weeklyWindow?.remainingPercent, 8)

        clock.advance(120)
        try writeCache(locations, fiveHour: (10, later), weekly: (40, later), capturedAt: clock.now, profile: Self.profile)
        let expired = try await provider.readUsage(userInitiated: true)
        XCTAssertNil(expired.weeklyWindow)
        XCTAssertTrue(expired.weeklyUnavailable)
        XCTAssertEqual(expired.fiveHourWindow?.remainingPercent, 90)
        XCTAssertEqual(expired.subLimit, fable, "Fable has its own reset and stays")
    }

    func testRejectionOutlivesAMissingAllModelsRow() async throws {
        let locations = try makeLocations()
        defer { try? FileManager.default.removeItem(at: locations.homeDirectory) }
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let reset = now.addingTimeInterval(86_400)
        let fable = SubLimit(name: "Fable", window: UsageWindow(usedPercent: 30, resetsAt: reset))
        let cli = ScriptedCLI([
            .reading(weekly: UsageWindow(usedPercent: 92, resetsAt: reset), fable: nil),
            .found(fable),
            .absent,
            .absent
        ])
        let clock = TestClock(now)
        let reader = SubLimitReader(configProfile: Self.profile, fetch: { await cli.fetch() }, now: { clock.now })
        let provider = ClaudeUsageProvider(locations: locations, subLimitReader: reader)

        try writeCache(locations, weekly: (54, reset), capturedAt: now, profile: Self.profile)
        _ = try await provider.readUsage(userInitiated: true)

        // /usage printed Fable but no all-models row.
        clock.advance(61)
        try writeCache(locations, weekly: (54, reset), capturedAt: clock.now, profile: Self.profile)
        let missingRow = try await provider.readUsage(userInitiated: true)
        XCTAssertNil(missingRow.weeklyWindow)
        XCTAssertTrue(missingRow.weeklyUnavailable)
        XCTAssertEqual(missingRow.currentSubLimit(now: clock.now), fable)
        XCTAssertNil(missingRow.displayCapturedAt(now: clock.now), "Fable cannot give a rejected redraw an update age")
        XCTAssertNil(missingRow.freshness(now: clock.now))

        // Output with neither row.
        clock.advance(61)
        try writeCache(locations, weekly: (54, reset), capturedAt: clock.now, profile: Self.profile)
        let unparseable = try await provider.readUsage(userInitiated: true)
        XCTAssertNil(unparseable.weeklyWindow)
        XCTAssertNil(unparseable.subLimit)
        XCTAssertTrue(unparseable.weeklyUnavailable)
        XCTAssertNil(unparseable.displayCapturedAt(now: clock.now), "A rejected redraw has no update age")
        XCTAssertNil(unparseable.freshness(now: clock.now))

        clock.advance(61)
        try writeCache(locations, weekly: (60, reset), capturedAt: clock.now, profile: Self.profile)
        let changed = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(changed.weeklyWindow?.remainingPercent, 40)
    }

    func testMissingAllModelsRowRetriesOnNextMinuteOfActivity() async throws {
        let locations = try makeLocations()
        defer { try? FileManager.default.removeItem(at: locations.homeDirectory) }
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let reset = now.addingTimeInterval(86_400)
        let fable = SubLimit(name: "Fable", window: UsageWindow(usedPercent: 30, resetsAt: reset))
        let cli = ScriptedCLI([
            .reading(weekly: UsageWindow(usedPercent: 92, resetsAt: reset), fable: nil),
            .found(fable),
            .reading(weekly: UsageWindow(usedPercent: 93, resetsAt: reset), fable: fable)
        ])
        let clock = TestClock(now)
        let reader = SubLimitReader(configProfile: Self.profile, fetch: { await cli.fetch() }, now: { clock.now })
        let provider = ClaudeUsageProvider(locations: locations, subLimitReader: reader)

        try writeCache(locations, weekly: (54, reset), capturedAt: now, profile: Self.profile)
        _ = try await provider.readUsage(userInitiated: true)
        clock.advance(61)
        try writeCache(locations, weekly: (54, reset), capturedAt: clock.now, profile: Self.profile)
        let missingRow = try await provider.readUsage(userInitiated: true)
        XCTAssertTrue(missingRow.weeklyUnavailable)

        // A background read a minute later, after new status-line activity.
        clock.advance(61)
        try writeCache(locations, fiveHour: (10, reset), weekly: (54, reset), capturedAt: clock.now, profile: Self.profile)
        _ = try await provider.readUsage()
        try await Task.sleep(for: .milliseconds(100))
        let recovered = try await provider.readUsage()
        XCTAssertEqual(recovered.weeklyWindow?.remainingPercent, 7)
        XCTAssertFalse(recovered.weeklyUnavailable)
    }

    // MARK: - Readings written while /usage runs

    /// The CLI may ask Anthropic for usage at the start of a 15-second run.
    /// A lower reading the status line captures later in that run may be a
    /// correction the CLI never saw, so it is not rejected, and it shows
    /// once the next check fails.
    func testLowerReadingWrittenDuringCheckIsNotRejected() async throws {
        let locations = try makeLocations()
        defer { try? FileManager.default.removeItem(at: locations.homeDirectory) }
        let rounding = CaptureRunner.capturedAtRounding
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / rounding) * rounding)
        let reset = now.addingTimeInterval(86_400)
        let clock = TestClock(now)
        let profile = Self.profile
        let runs = ScriptedCLI([.failed])
        let first = FirstRun()
        let reader = SubLimitReader(configProfile: profile, fetch: {
            guard await first.claim() else { return await runs.fetch() }
            clock.advance(5)
            try? Self.writeCache(locations, weekly: (54, reset), capturedAt: clock.now, profile: profile)
            clock.advance(10)
            return .reading(weekly: UsageWindow(usedPercent: 92, resetsAt: reset), fable: nil)
        }, now: { clock.now })
        let provider = ClaudeUsageProvider(locations: locations, subLimitReader: reader)

        try writeCache(locations, weekly: (92, reset), capturedAt: now.addingTimeInterval(-60), profile: profile)
        let initial = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(initial.weeklyWindow?.remainingPercent, 8, "The successful check still stands")

        clock.advance(61)
        let failed = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(failed.weeklyWindow?.remainingPercent, 46)
        XCTAssertEqual(failed.weeklyCapturedAt, now.addingTimeInterval(5))
        XCTAssertFalse(failed.weeklyUnavailable)
    }

    /// The same redraw is caught by the next successful check, which reads it
    /// before starting, and stays rejected through later failures.
    func testStaleRedrawWrittenDuringCheckIsRejectedByTheNextCheck() async throws {
        let locations = try makeLocations()
        defer { try? FileManager.default.removeItem(at: locations.homeDirectory) }
        let rounding = CaptureRunner.capturedAtRounding
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / rounding) * rounding)
        let reset = now.addingTimeInterval(86_400)
        let clock = TestClock(now)
        let profile = Self.profile
        let runs = ScriptedCLI([.reading(weekly: UsageWindow(usedPercent: 92, resetsAt: reset), fable: nil), .failed])
        let first = FirstRun()
        let reader = SubLimitReader(configProfile: profile, fetch: {
            guard await first.claim() else { return await runs.fetch() }
            try? Self.writeCache(locations, weekly: (54, reset), capturedAt: clock.now, profile: profile)
            clock.advance(15)
            return .reading(weekly: UsageWindow(usedPercent: 92, resetsAt: reset), fable: nil)
        }, now: { clock.now })
        let provider = ClaudeUsageProvider(locations: locations, subLimitReader: reader)

        try writeCache(locations, weekly: (92, reset), capturedAt: now, profile: profile)
        _ = try await provider.readUsage(userInitiated: true)

        clock.advance(61)
        try writeCache(locations, weekly: (54, reset), capturedAt: clock.now, profile: profile)
        let rechecked = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(rechecked.weeklyWindow?.remainingPercent, 8)

        clock.advance(61)
        try writeCache(locations, weekly: (54, reset), capturedAt: clock.now, profile: profile)
        let redrawn = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(redrawn.weeklyWindow?.remainingPercent, 8, "A known-rejected redraw is not a fallback")
    }

    func testNewUsageWrittenDuringCheckIsNotRejected() async throws {
        let locations = try makeLocations()
        defer { try? FileManager.default.removeItem(at: locations.homeDirectory) }
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let reset = now.addingTimeInterval(86_400)
        let clock = TestClock(now)
        let profile = Self.profile
        let runs = ScriptedCLI(Array(repeating: .failed, count: 2))
        let first = FirstRun()
        let reader = SubLimitReader(configProfile: profile, fetch: {
            guard await first.claim() else { return await runs.fetch() }
            // An active session reports usage the check may predate.
            try? Self.writeCache(locations, weekly: (95, reset), capturedAt: clock.now, profile: profile)
            return .reading(weekly: UsageWindow(usedPercent: 92, resetsAt: reset), fable: nil)
        }, now: { clock.now })
        let provider = ClaudeUsageProvider(locations: locations, subLimitReader: reader)

        try writeCache(locations, weekly: (92, reset), capturedAt: now, profile: profile)
        _ = try await provider.readUsage(userInitiated: true)

        clock.advance(61)
        try writeCache(locations, weekly: (95, reset), capturedAt: clock.now, profile: profile)
        let later = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(later.weeklyWindow?.remainingPercent, 5)
    }

    /// `/usage` finishes at 12:00:03. A lower-usage correction captured at
    /// 12:00:05 is stamped 12:00:00, so it may follow the check.
    func testCorrectionStampedBeforeTheCheckEndedIsNotRejected() async throws {
        let locations = try makeLocations()
        defer { try? FileManager.default.removeItem(at: locations.homeDirectory) }
        let rounding = CaptureRunner.capturedAtRounding
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / rounding) * rounding)
        let reset = now.addingTimeInterval(86_400)
        let clock = TestClock(now)
        let runs = ScriptedCLI([.failed])
        let first = FirstRun()
        let reader = SubLimitReader(configProfile: Self.profile, fetch: {
            guard await first.claim() else { return await runs.fetch() }
            clock.advance(3)
            return .reading(weekly: UsageWindow(usedPercent: 92, resetsAt: reset), fable: nil)
        }, now: { clock.now })
        let provider = ClaudeUsageProvider(locations: locations, subLimitReader: reader)

        try writeCache(locations, weekly: (92, reset), capturedAt: now.addingTimeInterval(-60), profile: Self.profile)
        _ = try await provider.readUsage(userInitiated: true)

        clock.advance(2)
        try writeCache(locations, weekly: (54, reset), capturedAt: now, profile: Self.profile)
        let settled = try await provider.readUsage()
        XCTAssertEqual(settled.weeklyWindow?.remainingPercent, 8, "The successful check still stands")

        // /usage then fails: the correction is the newest trustworthy value.
        clock.advance(61)
        let failed = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(failed.weeklyWindow?.remainingPercent, 46)
        XCTAssertEqual(failed.weeklyCapturedAt, now)
        XCTAssertFalse(failed.weeklyUnavailable)
    }

    func testOtherProfileReadingIsNeverRejected() async throws {
        let locations = try makeLocations()
        defer { try? FileManager.default.removeItem(at: locations.homeDirectory) }
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let reset = now.addingTimeInterval(86_400)
        let cli = ScriptedCLI([.reading(weekly: UsageWindow(usedPercent: 92, resetsAt: reset), fable: nil), .failed])
        let clock = TestClock(now)
        let reader = SubLimitReader(configProfile: Self.profile, fetch: { await cli.fetch() }, now: { clock.now })
        let provider = ClaudeUsageProvider(locations: locations, subLimitReader: reader)

        try writeCache(locations, weekly: (54, reset), capturedAt: now.addingTimeInterval(-60), profile: Self.otherProfile)
        let other = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(other.weeklyWindow?.remainingPercent, 46)

        // The same values later under this profile are not rejected by the
        // other login's reading.
        clock.advance(61)
        try writeCache(locations, weekly: (54, reset), capturedAt: clock.now, profile: Self.profile)
        let own = try await provider.readUsage(userInitiated: true)
        XCTAssertEqual(own.weeklyWindow?.remainingPercent, 46)
    }

    // MARK: - Helpers

    private actor FirstRun {
        private var claimed = false

        func claim() -> Bool {
            defer { claimed = true }
            return !claimed
        }
    }

    private actor Counter {
        let outcome: SubLimitReader.Outcome
        var calls = 0

        init(_ outcome: SubLimitReader.Outcome) { self.outcome = outcome }

        func fetch() -> SubLimitReader.Outcome {
            calls += 1
            return outcome
        }
    }

    private typealias CachedWindow = (used: Double, reset: Date)

    private func makeLocations() throws -> CacheLocations {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let locations = CacheLocations(homeDirectory: dir)
        try FileManager.default.createDirectory(at: locations.installDirectory, withIntermediateDirectories: true)
        return locations
    }

    private func writeCache(
        _ locations: CacheLocations,
        fiveHour: CachedWindow? = nil,
        weekly: CachedWindow?,
        capturedAt: Date,
        profile: String
    ) throws {
        try Self.writeCache(locations, fiveHour: fiveHour, weekly: weekly, capturedAt: capturedAt, profile: profile)
    }

    /// Static so a scripted CLI run can write the cache while it runs.
    private static func writeCache(
        _ locations: CacheLocations,
        fiveHour: CachedWindow? = nil,
        weekly: CachedWindow?,
        capturedAt: Date,
        profile: String
    ) throws {
        func window(_ window: CachedWindow) -> CacheWindow {
            CacheWindow(
                UsageWindow(usedPercent: window.used, resetsAt: window.reset),
                capturedAt: capturedAt.timeIntervalSince1970
            )
        }
        let payload = UsageCachePayload(
            fiveHour: fiveHour.map(window),
            sevenDay: weekly.map(window),
            capturedAt: capturedAt.timeIntervalSince1970,
            configDir: profile
        )
        try CaptureRunner.encode(payload).write(to: locations.cacheFile, options: .atomic)
    }
}
