import Foundation

struct CodexExecutableResolver: Sendable {
    private let environment: [String: String]
    private let homeDirectory: URL
    private let bundledCandidatePaths: [String]

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundledCandidatePaths: [String] = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex"
        ]
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.bundledCandidatePaths = bundledCandidatePaths
    }

    func resolve() -> URL? {
        var paths: [String] = []

        if let override = environment["CODEX_GAUGE_CODEX_PATH"], !override.isEmpty {
            paths.append((override as NSString).expandingTildeInPath)
        }

        if let path = environment["PATH"] {
            paths.append(contentsOf: path.split(separator: ":").map { "\($0)/codex" })
        }

        paths.append(contentsOf: knownCandidatePaths)

        var seen = Set<String>()
        for path in paths where seen.insert(path).inserted {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    func processEnvironment(for executable: URL) -> [String: String] {
        var childEnvironment = environment
        let pathDirectories = [
            executable.deletingLastPathComponent().path,
            homeDirectory.appendingPathComponent("Library/pnpm/bin").path,
            homeDirectory.appendingPathComponent(".local/bin").path,
            homeDirectory.appendingPathComponent(".volta/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]

        let existing = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        childEnvironment["PATH"] = unique(pathDirectories + existing).joined(separator: ":")
        return childEnvironment
    }

    private var knownCandidatePaths: [String] {
        // The bundled CLI is self-contained. Prefer it for GUI launches,
        // whose minimal PATH commonly cannot run package-manager shims
        // (for example, pnpm's shell wrapper needs `node` on PATH).
        bundledCandidatePaths + [
            homeDirectory.appendingPathComponent("Library/pnpm/bin/codex").path,
            homeDirectory.appendingPathComponent(".local/bin/codex").path,
            homeDirectory.appendingPathComponent(".volta/bin/codex").path,
            homeDirectory.appendingPathComponent(".npm-global/bin/codex").path,
            homeDirectory.appendingPathComponent(".bun/bin/codex").path,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
