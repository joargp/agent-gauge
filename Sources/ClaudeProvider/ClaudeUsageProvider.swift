import Foundation
import GaugeCore

/// Reads the usage cache written by the Claude Code statusline helper.
public struct ClaudeUsageProvider: UsageProvider {
    let locations: CacheLocations
    private let subLimitReader: SubLimitReader

    public init(locations: CacheLocations = CacheLocations()) {
        self.init(locations: locations, subLimitReader: SubLimitReader())
    }

    init(locations: CacheLocations, subLimitReader: SubLimitReader) {
        self.locations = locations
        self.subLimitReader = subLimitReader
    }

    public func readUsage() async throws -> UsageSnapshot {
        try await readUsage(userInitiated: false)
    }

    /// The CLI verifies the weekly limit independently of session redraws.
    /// The status line provides the 5-hour reading and a weekly fallback.
    ///
    /// The CLI reports on the app's Claude login. Its weekly reading is only
    /// combined with status-line windows captured under that same profile;
    /// caches from other profiles or older helpers show unchanged.
    public func readUsage(userInitiated: Bool) async throws -> UsageSnapshot {
        let cache = try readCache()
        let profile = subLimitReader.configProfile
        _ = await subLimitReader.currentReading(
            userInitiated: userInitiated,
            capturedAt: cache.snapshot.capturedAt,
            statuslineWeekly: cache.matches(profile) ? cache.snapshot.weeklyWindow : nil
        )
        // A statusline write may have landed while /usage was running.
        let latest = (try? readCache()) ?? cache
        let matches = latest.matches(profile)
        let reading = await subLimitReader.reconcile(
            statuslineWeekly: matches ? latest.snapshot.weeklyWindow : nil,
            capturedAt: latest.snapshot.weeklyCapturedAt
        )
        let fable = latest.conflicts(with: profile) ? nil : reading.fable
        guard matches else { return latest.snapshot.withSubLimit(fable) }

        let snapshot = latest.snapshot
        if let (weekly, checkedAt) = reading.verifiedWeekly(
            over: snapshot.weeklyWindow, capturedAt: snapshot.weeklyCapturedAt
        ) {
            return snapshot.replacingWeekly(weekly, capturedAt: checkedAt, subLimit: fable)
        }
        // No trustworthy weekly value: a reading a check showed to be wrong
        // is not a fallback. The 5-hour window and Fable stay as they are.
        if let statusline = snapshot.weeklyWindow, reading.rejects(statusline) {
            return snapshot.replacingWeekly(nil, capturedAt: nil, subLimit: fable)
        }
        return snapshot.withSubLimit(fable)
    }

    private struct CachedUsage {
        let snapshot: UsageSnapshot
        let configDir: String?

        /// At least one window was captured and its profile matches the CLI.
        func matches(_ profile: String?) -> Bool {
            guard let profile, ClaudeConfigProfile.identifiersMatch(configDir, profile) else { return false }
            return snapshot.fiveHourWindow != nil || snapshot.weeklyWindow != nil
        }

        /// Some stored window is known to come from another profile.
        func conflicts(with profile: String?) -> Bool {
            guard let profile, let configDir else { return false }
            return !ClaudeConfigProfile.identifiersMatch(configDir, profile)
        }
    }

    private func readCache() throws -> CachedUsage {
        let url = locations.cacheFile
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ClaudeUsageError.noCacheYet
        }
        do {
            let data = try Data(contentsOf: url)
            let payload = try UsageCacheDecoder.decodePayload(data)
            return CachedUsage(
                snapshot: try UsageCacheDecoder.snapshot(from: payload),
                configDir: payload.configDir
            )
        } catch let error as ClaudeUsageError {
            throw error
        } catch {
            throw ClaudeUsageError.unreadableCache
        }
    }

    public func setupGuidance() async -> String? {
        StatuslineInstallation.inspect(locations: locations).guidanceMessage
    }
}

private extension UsageSnapshot {
    /// A nil `weekly` marks the weekly reading unavailable.
    func replacingWeekly(_ weekly: UsageWindow?, capturedAt weeklyCapturedAt: Date?, subLimit: SubLimit?) -> UsageSnapshot {
        UsageSnapshot(
            fiveHourWindow: fiveHourWindow,
            weeklyWindow: weekly,
            badge: badge,
            capturedAt: capturedAt,
            subLimit: subLimit,
            fiveHourCapturedAt: fiveHourCapturedAt,
            weeklyCapturedAt: weeklyCapturedAt,
            weeklyUnavailable: weekly == nil
        )
    }
}
