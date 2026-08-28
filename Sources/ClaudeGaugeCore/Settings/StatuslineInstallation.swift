import Darwin
import Foundation

/// Safe file-system operations for installing, inspecting, and removing the
/// Claude Gauge statusline helper.
///
/// Settings changes fail closed: unreadable, malformed, foreign, and custom
/// integrated status lines are never replaced or removed. A companion lock
/// serializes Claude Gauge's own installers, and every mutation re-reads the
/// latest settings while holding that lock.
public enum StatuslineInstallation {
    private struct SettingsSnapshot: Equatable {
        let data: Data?
        let storageURL: URL
        let linkDestination: String?
    }

    /// Installs or repairs only the helper binary. This is used when a custom
    /// statusLine must be wired manually; settings are never read or changed.
    public static func installHelper(
        sourceExecutable: URL,
        locations: CacheLocations
    ) throws {
        let fileManager = FileManager.default
        try prepareClaudeDirectory(locations: locations, fileManager: fileManager)
        try withSettingsLock(locations: locations) {
            try prepareInstallDirectory(locations: locations, fileManager: fileManager)
            try installExecutable(
                from: sourceExecutable,
                to: locations.captureExecutable,
                fileManager: fileManager
            )
        }
    }

    public static func install(
        sourceExecutable: URL,
        locations: CacheLocations
    ) throws -> StatuslineChange {
        let fileManager = FileManager.default
        try prepareClaudeDirectory(locations: locations, fileManager: fileManager)

        return try withSettingsLock(locations: locations) {
            // Validate ownership before copying anything. Re-read again after
            // the copy so a concurrent settings update is merged or rejected.
            let preliminary = try readSettings(locations: locations, fileManager: fileManager)
            _ = try StatuslineSettings.apply(
                settingsJSON: preliminary.data,
                capturePath: locations.captureExecutable.path
            )

            try prepareInstallDirectory(locations: locations, fileManager: fileManager)

            try installExecutable(
                from: sourceExecutable,
                to: locations.captureExecutable,
                fileManager: fileManager
            )

            let latest = try readSettings(locations: locations, fileManager: fileManager)
            let result = try StatuslineSettings.apply(
                settingsJSON: latest.data,
                capturePath: locations.captureExecutable.path
            )

            switch result.change {
            case .installed, .updated:
                try writeSettings(
                    result.data,
                    expectedOriginal: latest,
                    locations: locations,
                    fileManager: fileManager
                )
            case .alreadyInstalled:
                break
            case .removed, .alreadyAbsent:
                assertionFailure("Unexpected install change: \(result.change)")
            }

            return result.change
        }
    }

    public static func uninstall(locations: CacheLocations) throws -> StatuslineChange {
        let fileManager = FileManager.default
        try prepareClaudeDirectory(locations: locations, fileManager: fileManager)

        return try withSettingsLock(locations: locations) {
            let current = try readSettings(locations: locations, fileManager: fileManager)
            let result = try StatuslineSettings.remove(
                settingsJSON: current.data,
                capturePath: locations.captureExecutable.path
            )

            if result.change == .removed {
                try writeSettings(
                    result.data,
                    expectedOriginal: current,
                    locations: locations,
                    fileManager: fileManager
                )
            }
            // The helper/cache are intentionally preserved. Project-local
            // Claude settings can reference them, and user settings alone
            // cannot prove that deletion is safe.
            return result.change
        }
    }

    public static func inspect(locations: CacheLocations) -> StatuslineInstallStatus {
        let fileManager = FileManager.default
        let state: StatuslineInstallStatus.State

        do {
            let settings = try readSettings(locations: locations, fileManager: fileManager)
            state = StatuslineSettings.inspect(
                settingsJSON: settings.data,
                capturePath: locations.captureExecutable.path
            )
        } catch {
            state = .unreadable
        }

        return StatuslineInstallStatus(
            state: state,
            captureBinaryExists: fileManager.isExecutableFile(
                atPath: locations.captureExecutable.path
            ),
            cacheFileExists: fileManager.fileExists(atPath: locations.cacheFile.path)
        )
    }

    private static func prepareClaudeDirectory(
        locations: CacheLocations,
        fileManager: FileManager
    ) throws {
        let claudeDirectory = locations.claudeSettingsFile.deletingLastPathComponent()
        let existed = fileManager.fileExists(atPath: claudeDirectory.path)
        try fileManager.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        if !existed {
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: claudeDirectory.path
            )
        }
    }

    private static func installExecutable(
        from source: URL,
        to destination: URL,
        fileManager: FileManager
    ) throws {
        let sourceData = try Data(contentsOf: source)
        let existingData = try? Data(contentsOf: destination)

        if existingData != sourceData {
            try sourceData.write(to: destination, options: .atomic)
        }

        // Always repair the executable bit, even when the bytes are already
        // identical after an interrupted or manually altered installation.
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: destination.path
        )
    }

    private static func prepareInstallDirectory(
        locations: CacheLocations,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: locations.installDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: locations.installDirectory.path
        )
    }

    private static func readSettings(
        locations: CacheLocations,
        fileManager: FileManager
    ) throws -> SettingsSnapshot {
        let logicalURL = locations.claudeSettingsFile.standardizedFileURL
        var metadata = stat()
        if lstat(logicalURL.path, &metadata) != 0 {
            if errno == ENOENT {
                return SettingsSnapshot(
                    data: nil,
                    storageURL: logicalURL,
                    linkDestination: nil
                )
            }
            throw ClaudeUsageError.unreadableSettings
        }
        let fileType = metadata.st_mode & mode_t(S_IFMT)
        guard fileType != mode_t(S_IFDIR) else {
            throw ClaudeUsageError.unreadableSettings
        }

        let storageURL: URL
        let linkDestination: String?
        if fileType == mode_t(S_IFLNK) {
            let destination: String
            do {
                destination = try fileManager.destinationOfSymbolicLink(
                    atPath: logicalURL.path
                )
            } catch {
                throw ClaudeUsageError.symlinkedSettings
            }
            linkDestination = destination
            if (destination as NSString).isAbsolutePath {
                storageURL = URL(fileURLWithPath: destination)
                    .standardizedFileURL
                    .resolvingSymlinksInPath()
            } else {
                storageURL = logicalURL.deletingLastPathComponent()
                    .appendingPathComponent(destination)
                    .standardizedFileURL
                    .resolvingSymlinksInPath()
            }

            var targetMetadata = stat()
            guard lstat(storageURL.path, &targetMetadata) == 0,
                  targetMetadata.st_mode & mode_t(S_IFMT) != mode_t(S_IFDIR)
            else {
                throw ClaudeUsageError.unreadableSettings
            }
        } else {
            storageURL = logicalURL
            linkDestination = nil
        }

        do {
            return SettingsSnapshot(
                data: try Data(contentsOf: storageURL),
                storageURL: storageURL,
                linkDestination: linkDestination
            )
        } catch {
            throw ClaudeUsageError.unreadableSettings
        }
    }

    private static func writeSettings(
        _ data: Data,
        expectedOriginal: SettingsSnapshot,
        locations: CacheLocations,
        fileManager: FileManager
    ) throws {
        let observed = try readSettings(locations: locations, fileManager: fileManager)
        guard observed == expectedOriginal else {
            throw ClaudeUsageError.concurrentSettingsChange
        }

        try data.write(to: expectedOriginal.storageURL, options: .atomic)
        if expectedOriginal.data == nil {
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: expectedOriginal.storageURL.path
            )
        }

        let verified = try readSettings(locations: locations, fileManager: fileManager)
        guard verified.data == data,
              verified.storageURL == expectedOriginal.storageURL,
              verified.linkDestination == expectedOriginal.linkDestination
        else {
            throw ClaudeUsageError.concurrentSettingsChange
        }
    }

    private static func withSettingsLock<T>(
        locations: CacheLocations,
        _ body: () throws -> T
    ) throws -> T {
        let lockURL = locations.claudeSettingsFile
            .deletingLastPathComponent()
            .appendingPathComponent(".claude-gauge-settings.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else {
            throw posixError()
        }
        defer { close(descriptor) }

        guard fchmod(descriptor, 0o600) == 0 else {
            throw posixError()
        }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw posixError()
        }
        defer { flock(descriptor, LOCK_UN) }

        return try body()
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
