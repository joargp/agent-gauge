import Darwin
import Foundation

protocol CodexUsageFetching: Sendable {
    func fetchUsage() async throws -> CodexUsageSnapshot
}

struct CodexAppServerClient: CodexUsageFetching, Sendable {
    private let resolver: CodexExecutableResolver
    private let timeout: TimeInterval

    init(
        resolver: CodexExecutableResolver = CodexExecutableResolver(),
        timeout: TimeInterval = 12
    ) {
        self.resolver = resolver
        self.timeout = timeout
    }

    func fetchUsage() async throws -> CodexUsageSnapshot {
        guard let executable = resolver.resolve() else {
            throw CodexUsageError.executableNotFound
        }
        let environment = resolver.processEnvironment(for: executable)
        let timeout = timeout

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let snapshot = try Self.fetchBlocking(
                        executable: executable,
                        environment: environment,
                        timeout: timeout
                    )
                    continuation.resume(returning: snapshot)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func fetchBlocking(
        executable: URL,
        environment: [String: String],
        timeout: TimeInterval
    ) throws -> CodexUsageSnapshot {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()

        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.environment = environment
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw CodexUsageError.launchFailed
        }

        let input = inputPipe.fileHandleForWriting
        let output = outputPipe.fileHandleForReading
        defer {
            try? input.close()
            try? output.close()
            stop(process)
        }

        try send(
            [
                "method": "initialize",
                "id": 0,
                "params": [
                    "clientInfo": [
                        "name": "codex_gauge",
                        "title": "Codex Gauge",
                        "version": "0.1.0"
                    ],
                    "capabilities": ["experimentalApi": false]
                ]
            ],
            to: input
        )

        var lineBuffer = JSONLineBuffer()
        var didInitialize = false
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let remainingMilliseconds = max(
                1,
                Int32(min(30_000, Date().distance(to: deadline) * 1_000))
            )
            var descriptor = pollfd(
                fd: output.fileDescriptor,
                events: Int16(POLLIN | POLLHUP),
                revents: 0
            )
            let pollResult = Darwin.poll(&descriptor, 1, remainingMilliseconds)

            if pollResult == 0 {
                throw CodexUsageError.timedOut
            }
            if pollResult < 0 {
                if errno == EINTR { continue }
                throw CodexUsageError.invalidResponse
            }

            var bytes = [UInt8](repeating: 0, count: 8_192)
            let bytesRead = Darwin.read(output.fileDescriptor, &bytes, bytes.count)
            if bytesRead < 0 {
                if errno == EINTR { continue }
                throw CodexUsageError.invalidResponse
            }
            let chunk = Data(bytes.prefix(bytesRead))

            if chunk.isEmpty {
                if !process.isRunning {
                    throw CodexUsageError.serverExited(process.terminationStatus)
                }
                continue
            }

            for line in lineBuffer.append(chunk) {
                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let identifier = (message["id"] as? NSNumber)?.intValue
                else {
                    continue
                }

                if identifier == 0, !didInitialize {
                    if let payload = rpcError(from: message) {
                        throw CodexRateLimitDecoder.classify(payload)
                    }
                    try send(["method": "initialized"], to: input)
                    try send(["method": "account/rateLimits/read", "id": 1], to: input)
                    didInitialize = true
                } else if identifier == 1 {
                    return try CodexRateLimitDecoder.decode(line)
                }
            }
        }

        throw CodexUsageError.timedOut
    }

    private static func send(_ object: [String: Any], to handle: FileHandle) throws {
        var data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: object)
            data.append(0x0A)
            try handle.write(contentsOf: data)
        } catch {
            throw CodexUsageError.invalidResponse
        }
    }

    private static func rpcError(from message: [String: Any]) -> RPCErrorPayload? {
        guard let error = message["error"] as? [String: Any],
              let text = error["message"] as? String
        else {
            return nil
        }
        return RPCErrorPayload(code: (error["code"] as? NSNumber)?.intValue, message: text)
    }

    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()

        for _ in 0..<20 where process.isRunning {
            usleep(25_000)
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
    }
}
