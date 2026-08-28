import Foundation
import ClaudeGaugeCore

protocol UsageReading: Sendable {
    func readUsage() async throws -> ClaudeUsageSnapshot
    func readInstallStatus() async -> StatuslineInstallStatus
}

struct LocalUsageReader: UsageReading {
    let locations: CacheLocations

    init(locations: CacheLocations = CacheLocations()) {
        self.locations = locations
    }

    func readUsage() async throws -> ClaudeUsageSnapshot {
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

    func readInstallStatus() async -> StatuslineInstallStatus {
        StatuslineInstallation.inspect(locations: locations)
    }
}
