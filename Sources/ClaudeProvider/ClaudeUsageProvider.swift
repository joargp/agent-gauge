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

    /// The 5-hour and weekly windows come from the status line cache. The
    /// Fable limit is optional extra data from the Claude CLI.
    public func readUsage(userInitiated: Bool) async throws -> UsageSnapshot {
        let snapshot = try readCache()
        let subLimit = await subLimitReader.current(userInitiated: userInitiated)
        return snapshot.withSubLimit(subLimit)
    }

    private func readCache() throws -> UsageSnapshot {
        let url = locations.cacheFile
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ClaudeUsageError.noCacheYet
        }
        do {
            let data = try Data(contentsOf: url)
            return try UsageCacheDecoder.decode(data)
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
