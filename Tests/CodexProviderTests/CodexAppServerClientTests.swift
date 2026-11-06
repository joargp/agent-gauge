import Foundation
import XCTest
@testable import CodexProvider

final class CodexAppServerClientTests: XCTestCase {
    func testClosedOutputFromRunningServerFailsPromptly() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let executable = directory.appendingPathComponent("codex")
        try "#!/bin/sh\nread -r request\nexec 1>&-\nexec /bin/sleep 10\n"
            .write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let resolver = CodexExecutableResolver(
            environment: ["CODEX_GAUGE_CODEX_PATH": executable.path, "PATH": "/usr/bin:/bin"],
            homeDirectory: directory,
            bundledCandidatePaths: []
        )
        let client = CodexAppServerClient(resolver: resolver, timeout: 5)
        let start = Date()

        do {
            _ = try await client.readUsage()
            XCTFail("Expected an error when the server closes its output")
        } catch let error as CodexUsageError {
            XCTAssertEqual(error, .invalidResponse)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
}
