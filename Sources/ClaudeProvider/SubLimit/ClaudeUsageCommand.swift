import Darwin
import Foundation
import GaugeCore

/// Runs `claude -p "/usage"` and reads the weekly windows from it. The command
/// is local: it makes no model call and costs nothing.
struct ClaudeUsageCommand: Sendable {
    private let resolver: ClaudeExecutableResolver
    private let timeout: TimeInterval

    /// Runs normally take 3 to 8 seconds; a busy Mac can take longer.
    init(resolver: ClaudeExecutableResolver = ClaudeExecutableResolver(), timeout: TimeInterval = 20) {
        self.resolver = resolver
        self.timeout = timeout
    }

    /// The Claude profile whose login `/usage` reports on. Nil when the
    /// app's own profile cannot be reproduced for the CLI, which then never
    /// runs rather than reading another login.
    var configProfile: String? { resolver.configProfile }

    func fetchUsage() async -> SubLimitReader.Outcome {
        guard let text = await fetchText() else { return .failed }
        return Self.parseUsage(text, now: Date())
    }

    static func parseUsage(_ text: String, now: Date) -> SubLimitReader.Outcome {
        let fable = ClaudeUsageTextParser.parseFable(text, now: now)
        if let weekly = ClaudeUsageTextParser.parseWeekly(text, now: now) {
            return .reading(weekly: weekly, fable: fable)
        }
        if let fable {
            return .found(fable)
        }
        return .absent
    }

    private func fetchText() async -> String? {
        guard resolver.configProfile != nil, let executable = resolver.resolve() else { return nil }
        let environment = resolver.processEnvironment(for: executable)
        let timeout = timeout

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                guard let output = Self.run(
                    executable: executable, environment: environment, timeout: timeout
                ) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: ClaudeUsageTextParser.resultText(fromJSON: output))
            }
        }
    }

    /// Standard output, or nil when the CLI fails or runs past the timeout.
    private static func run(
        executable: URL,
        environment: [String: String],
        timeout: TimeInterval
    ) -> Data? {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["-p", "/usage", "--output-format", "json", "--no-session-persistence"]
        process.environment = environment
        process.currentDirectoryURL = workingDirectory()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        // Drain the pipe while the process runs so a full pipe can't block it.
        let reader = output.fileHandleForReading
        let collected = Collected()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            collected.data = reader.readDataToEndOfFile()
            drained.signal()
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
            _ = drained.wait(timeout: .now() + 1)
            return nil
        }
        // Something else may still hold the pipe open. Treat that as a failure,
        // so `collected` is only read after the reader has finished with it.
        guard drained.wait(timeout: .now() + 2) == .success,
              process.terminationStatus == 0
        else { return nil }
        return collected.data
    }

    /// An empty folder of our own. macOS attributes the child's file access to
    /// Agent Gauge, so starting it in the home folder could make Claude Code's
    /// startup trigger privacy prompts for Desktop, Documents or Downloads.
    static func workingDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-gauge-claude", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            return FileManager.default.temporaryDirectory
        }
    }

    private final class Collected: @unchecked Sendable {
        var data = Data()
    }
}
