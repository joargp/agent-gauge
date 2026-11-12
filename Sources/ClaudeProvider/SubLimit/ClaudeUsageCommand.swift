import Darwin
import Foundation
import GaugeCore

/// Runs `claude -p "/usage"` and reads the Fable window from it. The command
/// is local: it makes no model call and costs nothing.
struct ClaudeUsageCommand: Sendable {
    private let resolver: ClaudeExecutableResolver
    private let timeout: TimeInterval

    init(resolver: ClaudeExecutableResolver = ClaudeExecutableResolver(), timeout: TimeInterval = 12) {
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
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
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
        _ = drained.wait(timeout: .now() + 2)
        guard process.terminationStatus == 0 else { return nil }
        return collected.data
    }

    private final class Collected: @unchecked Sendable {
        var data = Data()
    }
}
