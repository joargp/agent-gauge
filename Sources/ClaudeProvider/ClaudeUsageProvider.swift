import Foundation
import GaugeCore

/// Reads the usage cache written by the Claude Code statusline helper.
public struct ClaudeUsageProvider: UsageProvider {
    let locations: CacheLocations

    public init(locations: CacheLocations = CacheLocations()) {
        self.locations = locations
    }

    public func readUsage() async throws -> UsageSnapshot {
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
