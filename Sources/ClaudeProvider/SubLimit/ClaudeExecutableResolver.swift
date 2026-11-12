import Foundation

/// Finds the Claude Code CLI for a GUI app, whose PATH is minimal.
struct ClaudeExecutableResolver: Sendable {
    private let environment: [String: String]
    private let homeDirectory: URL

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    func resolve() -> URL? {
        var paths: [String] = []

        if let override = environment["CLAUDE_GAUGE_CLAUDE_PATH"], !override.isEmpty {
            paths.append((override as NSString).expandingTildeInPath)
        }
        if let path = environment["PATH"] {
            paths.append(contentsOf: path.split(separator: ":").map { "\($0)/claude" })
        }
        paths.append(contentsOf: [
            homeDirectory.appendingPathComponent(".local/bin/claude").path,
            homeDirectory.appendingPathComponent(".claude/local/claude").path,
            homeDirectory.appendingPathComponent("Library/pnpm/bin/claude").path,
            homeDirectory.appendingPathComponent(".volta/bin/claude").path,
            homeDirectory.appendingPathComponent(".npm-global/bin/claude").path,
            homeDirectory.appendingPathComponent(".bun/bin/claude").path,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ])

        var seen = Set<String>()
        for path in paths where seen.insert(path).inserted {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// The child's environment. API-key variables are removed because with
    /// them set, `/usage` prints API stats instead of subscription limits.
    func processEnvironment(for executable: URL) -> [String: String] {
        var child = environment
        child.removeValue(forKey: "ANTHROPIC_API_KEY")
        child.removeValue(forKey: "ANTHROPIC_AUTH_TOKEN")

        let directories = [
            executable.deletingLastPathComponent().path,
            homeDirectory.appendingPathComponent(".local/bin").path,
            homeDirectory.appendingPathComponent("Library/pnpm/bin").path,
            homeDirectory.appendingPathComponent(".volta/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        let existing = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        var seen = Set<String>()
        child["PATH"] = (directories + existing)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")
        return child
    }
}
