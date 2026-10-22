import Darwin
import Foundation
import ClaudeProvider

// Modes:
//   (no command)         read statusline JSON on stdin, update the usage
//                        cache, print a status line
//   install-helper       install only the capture binary for manual custom
//                        statusLine integration
//   install-statusline   install the capture binary and register the
//                        statusLine entry in ~/.claude/settings.json
//   uninstall-statusline remove the owned statusLine entry and helper files
//   status               print installation diagnostics
//
// `--home PATH` is an explicit test/diagnostic override. Installed statusline
// commands never use it, so the app and helper cannot silently split homes.
//
// Statusline mode never exits non-zero: a failing cache write must not break
// Claude Code's status line rendering.

let parsedArguments: (homeDirectory: URL, command: String?)
do {
    parsedArguments = try parseArguments(Array(CommandLine.arguments.dropFirst()))
} catch {
    fputs("usage: claude-gauge-capture [--home PATH] [install-helper|install-statusline|uninstall-statusline|status]\n", stderr)
    exit(64)
}

let locations = CacheLocations(homeDirectory: parsedArguments.homeDirectory)

switch parsedArguments.command {
case nil:
    runStatusline(locations: locations)
case "install-helper":
    exit(installHelper(locations: locations))
case "install-statusline":
    exit(installStatusline(locations: locations))
case "uninstall-statusline":
    exit(uninstallStatusline(locations: locations))
case "status":
    exit(printStatus(locations: locations))
default:
    fputs("usage: claude-gauge-capture [--home PATH] [install-helper|install-statusline|uninstall-statusline|status]\n", stderr)
    exit(64)
}

// MARK: - Arguments

private enum ArgumentError: Error {
    case invalid
}

private func parseArguments(_ rawArguments: [String]) throws -> (URL, String?) {
    var arguments = rawArguments
    var homeDirectory = FileManager.default.homeDirectoryForCurrentUser

    if arguments.first == "--home" {
        guard arguments.count >= 2, !arguments[1].isEmpty else {
            throw ArgumentError.invalid
        }
        homeDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
        arguments.removeFirst(2)
    }

    guard arguments.count <= 1 else {
        throw ArgumentError.invalid
    }
    return (homeDirectory, arguments.first)
}

// MARK: - Statusline mode

private func runStatusline(locations: CacheLocations) -> Never {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let now = Date()

    // Render first. Cache lock, read, or write failures must never suppress a
    // valid status line.
    guard let preview = try? CaptureRunner.run(
        input: input,
        existingCache: nil,
        now: now
    ) else {
        exit(0)
    }
    if !preview.statusLineText.isEmpty {
        print(preview.statusLineText)
    }

    do {
        try prepareCacheDirectory(locations: locations)
        try withCacheLock(locations: locations) {
            let existing = try readCacheIfPresent(locations.cacheFile)
            let outcome = try CaptureRunner.run(
                input: input,
                existingCache: existing,
                now: now
            )
            if let cacheData = outcome.cacheData {
                try cacheData.write(to: locations.cacheFile, options: .atomic)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: locations.cacheFile.path
                )
            }
        }
    } catch {
        // Intentionally silent: cache persistence is best-effort.
    }

    exit(0)
}

private func prepareCacheDirectory(locations: CacheLocations) throws {
    try FileManager.default.createDirectory(
        at: locations.installDirectory,
        withIntermediateDirectories: true
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: locations.installDirectory.path
    )
}

private func readCacheIfPresent(_ url: URL) throws -> Data? {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
        return nil
    }
    guard !isDirectory.boolValue else {
        throw CocoaError(.fileReadUnknown)
    }
    return try Data(contentsOf: url)
}

private func withCacheLock(
    locations: CacheLocations,
    _ body: () throws -> Void
) throws {
    let lockURL = locations.installDirectory.appendingPathComponent(".cache.lock")
    let descriptor = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
    guard descriptor >= 0 else { throw posixError() }
    defer { close(descriptor) }

    guard fchmod(descriptor, 0o600) == 0 else { throw posixError() }
    guard flock(descriptor, LOCK_EX) == 0 else { throw posixError() }
    defer { flock(descriptor, LOCK_UN) }

    try body()
}

private func posixError() -> NSError {
    NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
}

// MARK: - Install / uninstall

private func installHelper(locations: CacheLocations) -> Int32 {
    do {
        let sourceExecutable = try currentExecutableURL()
        try StatuslineInstallation.installHelper(
            sourceExecutable: sourceExecutable,
            locations: locations
        )
        print("capture helper installed: \(locations.captureExecutable.path)")
        return 0
    } catch {
        fputs("claude-gauge-capture install-helper failed: \(localizedDescription(error))\n", stderr)
        return 1
    }
}

private func installStatusline(locations: CacheLocations) -> Int32 {
    do {
        let sourceExecutable = try currentExecutableURL()
        let change = try StatuslineInstallation.install(
            sourceExecutable: sourceExecutable,
            locations: locations
        )
        print("statusLine \(describe(change)): \(locations.captureExecutable.path)")
        return 0
    } catch {
        fputs("claude-gauge-capture install-statusline failed: \(localizedDescription(error))\n", stderr)
        return 1
    }
}

private func uninstallStatusline(locations: CacheLocations) -> Int32 {
    do {
        let change = try StatuslineInstallation.uninstall(locations: locations)
        print("Agent Gauge status line \(describe(change))")
        print("Helper and cache preserved for possible project-level references: \(locations.installDirectory.path)")
        return 0
    } catch {
        fputs("claude-gauge-capture uninstall-statusline failed: \(localizedDescription(error))\n", stderr)
        return 1
    }
}

private func printStatus(locations: CacheLocations) -> Int32 {
    let status = StatuslineInstallation.inspect(locations: locations)

    print("capture: \(locations.captureExecutable.path)")
    print("  binary: \(status.captureBinaryExists ? "present" : "MISSING")")
    print("cache:   \(locations.cacheFile.path)")
    print("  file:   \(status.cacheFileExists ? "present" : "not written yet")")
    print("statusLine: \(describe(status.state))")
    return 0
}

private func localizedDescription(_ error: Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
}

private func currentExecutableURL() throws -> URL {
    if let executableURL = Bundle.main.executableURL {
        return executableURL.standardizedFileURL.resolvingSymlinksInPath()
    }
    throw CocoaError(.executableNotLoadable)
}

private func describe(_ change: StatuslineChange) -> String {
    switch change {
    case .installed: "installed"
    case .updated: "updated"
    case .alreadyInstalled: "already installed"
    case .removed: "removed"
    case .alreadyAbsent: "not present"
    }
}

private func describe(_ state: StatuslineInstallStatus.State) -> String {
    switch state {
    case let .installed(command): "registered (\(command))"
    case let .integrated(command): "integrated with custom status line (\(command))"
    case .missing: "not configured"
    case let .foreign(command): "foreign (\(command))"
    case .malformed: "malformed statusLine value"
    case .unreadable: "unreadable settings"
    }
}
