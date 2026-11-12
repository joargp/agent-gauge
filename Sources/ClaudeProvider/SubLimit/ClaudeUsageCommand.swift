import Darwin
import Foundation
import GaugeCore

/// Runs `claude -p "/usage"` and reads the Fable window from it. The command
/// is local: it makes no model call and costs nothing.
struct ClaudeUsageCommand: Sendable {
    private let resolver: ClaudeExecutableResolver
    private let timeout: TimeInterval

    /// Runs normally take 3 to 8 seconds; a busy Mac can take longer.
    init(resolver: ClaudeExecutableResolver = ClaudeExecutableResolver(), timeout: TimeInterval = 20) {
        self.resolver = resolver
        self.timeout = timeout
    }

    func fetch() async -> SubLimitReader.Outcome {
        guard let executable = resolver.resolve() else { return .failed }
        let environment = resolver.processEnvironment(for: executable)
        let timeout = timeout

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                guard let output = Self.run(
                    executable: executable, environment: environment, timeout: timeout
                ), let text = ClaudeUsageTextParser.resultText(fromJSON: output) else {
                    continuation.resume(returning: .failed)
                    return
                }
                if let fable = ClaudeUsageTextParser.parseFable(text) {
                    continuation.resume(returning: .found(fable))
                } else {
                    continuation.resume(returning: .absent)
                }
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
