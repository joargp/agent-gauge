import Foundation
import XCTest
@testable import ClaudeProvider

final class ClaudeExecutableResolverTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
    private let claude = URL(fileURLWithPath: "/usr/local/bin/claude")

    func testImplicitProfileDoesNotOverrideClaudeLoginLookup() {
        let resolver = ClaudeExecutableResolver(environment: [:], homeDirectory: home)
        XCTAssertEqual(resolver.configProfile, "/Users/test/.claude")
        XCTAssertNil(resolver.processEnvironment(for: claude)["CLAUDE_CONFIG_DIR"])
    }

    func testExplicitDefaultFolderIsADifferentProfileFromImplicit() {
        let implicit = ClaudeExecutableResolver(environment: [:], homeDirectory: home)
        let explicit = ClaudeExecutableResolver(environment: ["CLAUDE_CONFIG_DIR": "/Users/test/.claude"], homeDirectory: home)
        XCTAssertEqual(explicit.configProfile, "override:/Users/test/.claude")
        XCTAssertNotEqual(explicit.configProfile, implicit.configProfile)
        XCTAssertEqual(explicit.processEnvironment(for: claude)["CLAUDE_CONFIG_DIR"], "/Users/test/.claude")
    }

    /// Claude Code names the Keychain item after the literal value, so
    /// spellings of the same folder are separate logins.
    func testAbsoluteOverrideIsPassedAndMatchedLiterally() {
        let literals = ["/Users/test/.claude/", "/Users/test/work/../.claude-work", "/Users/test/.claude-work"]
        var profiles = Set<String>()
        for literal in literals {
            let resolver = ClaudeExecutableResolver(environment: ["CLAUDE_CONFIG_DIR": literal], homeDirectory: home)
            XCTAssertEqual(resolver.configProfile, "override:\(literal)")
            XCTAssertEqual(resolver.processEnvironment(for: claude)["CLAUDE_CONFIG_DIR"], literal)
            resolver.configProfile.map { _ = profiles.insert($0) }
        }
        XCTAssertEqual(profiles.count, literals.count)
    }

    func testRelativeOrEmptyOverrideCannotBeVerified() {
        for literal in ["./test-claude-profile", "test-claude-profile", "~/.claude-work", "", " "] {
            let resolver = ClaudeExecutableResolver(environment: ["CLAUDE_CONFIG_DIR": literal], homeDirectory: home)
            XCTAssertNil(resolver.configProfile, "\(literal.debugDescription) resolves against the CLI's working folder")
        }
    }

    // MARK: - Keychain namespace (CLAUDE_SECURESTORAGE_CONFIG_DIR)

    func testSecureStorageDirSeparatesLoginsWithTheSameConfigDir() {
        let config = "/Users/test/.claude-work"
        func resolver(_ storage: String?) -> ClaudeExecutableResolver {
            var environment = ["CLAUDE_CONFIG_DIR": config]
            environment["CLAUDE_SECURESTORAGE_CONFIG_DIR"] = storage
            return ClaudeExecutableResolver(environment: environment, homeDirectory: home)
        }
        let unset = resolver(nil)
        XCTAssertEqual(unset.configProfile, "override:\(config)", "Unchanged without the variable")

        // Literal values, so spellings of one folder stay separate logins.
        let literals = ["/Users/test/keychain-a", "/Users/test/keychain-b", "/Users/test/keychain-a/", config]
        var profiles: Set<String?> = [unset.configProfile]
        for literal in literals {
            let resolver = resolver(literal)
            XCTAssertNotNil(resolver.configProfile)
            XCTAssertEqual(resolver.processEnvironment(for: claude)["CLAUDE_SECURESTORAGE_CONFIG_DIR"], literal)
            XCTAssertEqual(resolver.processEnvironment(for: claude)["CLAUDE_CONFIG_DIR"], config)
            profiles.insert(resolver.configProfile)
        }
        XCTAssertEqual(profiles.count, literals.count + 1)
        XCTAssertEqual(resolver("/Users/test/keychain-a").configProfile, resolver("/Users/test/keychain-a").configProfile)
    }

    func testSecureStorageDirAlsoSeparatesTheDefaultConfigDir() {
        let implicit = ClaudeExecutableResolver(environment: [:], homeDirectory: home)
        let storage = ClaudeExecutableResolver(
            environment: ["CLAUDE_SECURESTORAGE_CONFIG_DIR": "/Users/test/keychain-a"], homeDirectory: home
        )
        XCTAssertNotNil(storage.configProfile)
        XCTAssertNotEqual(storage.configProfile, implicit.configProfile)
        let child = storage.processEnvironment(for: claude)
        XCTAssertNil(child["CLAUDE_CONFIG_DIR"])
        XCTAssertEqual(child["CLAUDE_SECURESTORAGE_CONFIG_DIR"], "/Users/test/keychain-a")
        XCTAssertNil(implicit.processEnvironment(for: claude)["CLAUDE_SECURESTORAGE_CONFIG_DIR"])
    }

    func testRelativeOrEmptySecureStorageDirCannotBeVerified() {
        for configDir in [nil, "/Users/test/.claude-work"] as [String?] {
            for literal in ["keychain", "./keychain", "~/keychain", "", " "] {
                var environment = ["CLAUDE_SECURESTORAGE_CONFIG_DIR": literal]
                environment["CLAUDE_CONFIG_DIR"] = configDir
                let resolver = ClaudeExecutableResolver(environment: environment, homeDirectory: home)
                XCTAssertNil(resolver.configProfile, "\(literal.debugDescription) is not passed on unchanged")
            }
        }
    }

    /// The helper records the same identifier the app derives, so a
    /// capture made under the app's exact environment matches it.
    func testHelperIdentifierMatchesTheAppForTheSameEnvironment() {
        let environments: [[String: String]] = [
            [:],
            ["CLAUDE_CONFIG_DIR": "/Users/test/.claude-work"],
            ["CLAUDE_SECURESTORAGE_CONFIG_DIR": "/Users/test/keychain-a"],
            ["CLAUDE_CONFIG_DIR": "/Users/test/.claude-work", "CLAUDE_SECURESTORAGE_CONFIG_DIR": "/Users/test/keychain-a"]
        ]
        for environment in environments {
            let app = ClaudeExecutableResolver(environment: environment, homeDirectory: home).configProfile
            let helper = ClaudeConfigProfile.identifier(
                environment: environment, homeDirectory: home, currentDirectory: "/Users/test/project"
            )
            XCTAssertEqual(app, helper, "\(environment)")
        }
    }

    func testHelperIdentifierForRelativeSecureStorageNeverMatchesTheApp() {
        func helper(_ storage: String, cwd: String) -> String {
            ClaudeConfigProfile.identifier(
                environment: ["CLAUDE_CONFIG_DIR": "/Users/test/.claude-work", "CLAUDE_SECURESTORAGE_CONFIG_DIR": storage],
                homeDirectory: home,
                currentDirectory: cwd
            )
        }
        let relative = helper("keychain", cwd: "/Users/test/a")
        XCTAssertEqual(relative, helper("keychain", cwd: "/Users/test/a"))
        XCTAssertNotEqual(relative, helper("keychain", cwd: "/Users/test/b"))
        XCTAssertNotEqual(relative, helper("./keychain", cwd: "/Users/test/a"))
        XCTAssertNotEqual(helper("", cwd: "/Users/test"), helper(" ", cwd: "/Users/test"))
        let app = ClaudeExecutableResolver(
            environment: ["CLAUDE_CONFIG_DIR": "/Users/test/.claude-work", "CLAUDE_SECURESTORAGE_CONFIG_DIR": "/Users/test/a/keychain"],
            homeDirectory: home
        ).configProfile
        XCTAssertNotEqual(relative, app, "Same folder, different literal and Keychain item")
    }

    func testCLIGetsTheExactSecureStorageDir() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let marker = dir.appendingPathComponent("config-dir")
        let fake = try makeFakeClaude(in: dir, marker: marker)
        let literal = dir.path + "/keychain/../keychain/"

        let command = ClaudeUsageCommand(resolver: ClaudeExecutableResolver(
            environment: ["CLAUDE_GAUGE_CLAUDE_PATH": fake.path, "CLAUDE_SECURESTORAGE_CONFIG_DIR": literal, "PATH": ""],
            homeDirectory: dir
        ))
        guard case .found = await command.fetchUsage() else { return XCTFail("Expected a Fable reading") }
        XCTAssertEqual(try String(contentsOf: secureStorageMarker(marker), encoding: .utf8), literal)
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "", "CLAUDE_CONFIG_DIR stays unset")
    }

    func testCLIDoesNotRunForARelativeSecureStorageDir() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let marker = dir.appendingPathComponent("config-dir")
        let fake = try makeFakeClaude(in: dir, marker: marker)

        let command = ClaudeUsageCommand(resolver: ClaudeExecutableResolver(
            environment: ["CLAUDE_GAUGE_CLAUDE_PATH": fake.path, "CLAUDE_SECURESTORAGE_CONFIG_DIR": "keychain", "PATH": ""],
            homeDirectory: dir
        ))
        XCTAssertNil(command.configProfile)
        guard case .failed = await command.fetchUsage() else { return XCTFail("Expected no reading") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "Running it would read another login")
    }

    func testCLIGetsTheExactAbsoluteOverride() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let marker = dir.appendingPathComponent("config-dir")
        let fake = try makeFakeClaude(in: dir, marker: marker)
        let literal = dir.path + "/profile/../profile/"

        let command = ClaudeUsageCommand(resolver: ClaudeExecutableResolver(
            environment: ["CLAUDE_GAUGE_CLAUDE_PATH": fake.path, "CLAUDE_CONFIG_DIR": literal, "PATH": ""],
            homeDirectory: dir
        ))
        guard case .found = await command.fetchUsage() else { return XCTFail("Expected a Fable reading") }
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), literal)
        XCTAssertEqual(try String(contentsOf: secureStorageMarker(marker), encoding: .utf8), "<unset>")
    }

    func testCLIDoesNotRunForARelativeOverride() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let marker = dir.appendingPathComponent("config-dir")
        let fake = try makeFakeClaude(in: dir, marker: marker)

        let command = ClaudeUsageCommand(resolver: ClaudeExecutableResolver(
            environment: ["CLAUDE_GAUGE_CLAUDE_PATH": fake.path, "CLAUDE_CONFIG_DIR": "./profile", "PATH": ""],
            homeDirectory: dir
        ))
        XCTAssertNil(command.configProfile)
        guard case .failed = await command.fetchUsage() else { return XCTFail("Expected no reading") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "Running it would read another login")
    }

    func testCLIDoesNotRunWhenOAuthTokenIsSetOnApp() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let marker = dir.appendingPathComponent("config-dir")
        let bin = dir.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let fake = try makeFakeClaude(in: bin, marker: marker)

        for fixture in ["test-token", ""] {
            let resolver = ClaudeExecutableResolver(environment: [
                "CLAUDE_GAUGE_CLAUDE_PATH": fake.path,
                "CLAUDE_CODE_OAUTH_TOKEN": fixture,
                "CLAUDE_CONFIG_DIR": dir.path,
                "CLAUDE_SECURESTORAGE_CONFIG_DIR": dir.path,
                "PATH": ""
            ], homeDirectory: dir)
            let command = ClaudeUsageCommand(resolver: resolver)
            XCTAssertNil(command.configProfile)
            XCTAssertEqual(resolver.resolve(), fake, "The CLI exists but must not run")
            XCTAssertFalse(resolver.processEnvironment(for: fake).keys.contains("CLAUDE_CODE_OAUTH_TOKEN"))
            guard case .failed = await command.fetchUsage() else { return XCTFail("Expected no reading") }
            XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "Neither OAuth nor Keychain /usage should run")
        }
    }

    // MARK: - Helpers

    private func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func secureStorageMarker(_ marker: URL) -> URL {
        marker.appendingPathExtension("securestorage")
    }

    /// Records the `CLAUDE_CONFIG_DIR` and `CLAUDE_SECURESTORAGE_CONFIG_DIR`
    /// it was given and prints `/usage` JSON.
    private func makeFakeClaude(in dir: URL, marker: URL) throws -> URL {
        let fake = dir.appendingPathComponent("claude")
        let script = """
        #!/bin/sh
        printf '%s' "$CLAUDE_CONFIG_DIR" > '\(marker.path)'
        printf '%s' "${CLAUDE_SECURESTORAGE_CONFIG_DIR-<unset>}" > '\(secureStorageMarker(marker).path)'
        printf '%s' '{"result":"Current week (Fable): 40% used"}'
        """
        try script.write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        return fake
    }
}
