import Foundation
import XCTest
@testable import CodexGauge

final class CodexExecutableResolverTests: XCTestCase {
    func testFindsPnpmInstallWhenFinderPathDoesNotContainIt() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bin = home.appendingPathComponent("Library/pnpm/bin", isDirectory: true)
        let executable = bin.appendingPathComponent("codex")
        defer { try? FileManager.default.removeItem(at: home) }

        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data("#!/bin/sh\n".utf8)))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let resolver = CodexExecutableResolver(
            environment: ["PATH": "/usr/bin:/bin"],
            homeDirectory: home,
            bundledCandidatePaths: []
        )

        XCTAssertEqual(resolver.resolve()?.path, executable.path)
    }

    func testPrefersBundledCLIOverPackageManagerShim() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = directory.appendingPathComponent("home", isDirectory: true)
        let pnpmExecutable = home.appendingPathComponent("Library/pnpm/bin/codex")
        let bundledExecutable = directory.appendingPathComponent("ChatGPT.app/Contents/Resources/codex")
        defer { try? FileManager.default.removeItem(at: directory) }

        for executable in [pnpmExecutable, bundledExecutable] {
            try FileManager.default.createDirectory(
                at: executable.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data("#!/bin/sh\n".utf8)))
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        }

        let resolver = CodexExecutableResolver(
            environment: ["PATH": "/usr/bin:/bin"],
            homeDirectory: home,
            bundledCandidatePaths: [bundledExecutable.path]
        )

        XCTAssertEqual(resolver.resolve()?.path, bundledExecutable.path)
    }

    func testExplicitOverrideTakesPriority() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let executable = directory.appendingPathComponent("custom-codex")
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let resolver = CodexExecutableResolver(
            environment: ["CODEX_GAUGE_CODEX_PATH": executable.path, "PATH": ""],
            homeDirectory: directory
        )

        XCTAssertEqual(resolver.resolve()?.path, executable.path)
    }
}
