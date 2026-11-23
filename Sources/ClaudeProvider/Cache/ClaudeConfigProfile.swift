import Darwin
import Foundation

/// Identifies which Claude Code configuration (and so which login) a reading
/// came from. No account details or credentials are read or stored.
///
/// For Keychain logins, `CLAUDE_CONFIG_DIR` picks the config
/// folder and, by default, the Keychain item. `CLAUDE_SECURESTORAGE_CONFIG_DIR`,
/// when set, picks the Keychain item instead, so two sessions with the same
/// `CLAUDE_CONFIG_DIR` can still use different logins.
public enum ClaudeConfigProfile {
    static let environmentKey = "CLAUDE_CONFIG_DIR"
    static let secureStorageKey = "CLAUDE_SECURESTORAGE_CONFIG_DIR"
    private static let oauthTokenKey = "CLAUDE_CODE_OAUTH_TOKEN"
    /// Marks an explicit token login, not a specific account or Keychain profile.
    private static let explicitOAuth = "explicit-oauth"

    static func canMergeWindows(previous: String?, incoming: String?) -> Bool {
        identifiersMatch(previous, incoming) && !identifiersMatch(incoming, explicitOAuth)
    }

    /// Profile IDs are opaque UTF-8, not human-readable names. Swift's String
    /// equality treats canonically equivalent spellings as equal; we only
    /// combine data when the identifiers have exactly the same bytes.
    static func identifiersMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): lhs.utf8.elementsEqual(rhs.utf8)
        case (nil, nil): true
        default: false
        }
    }

    /// Nil when an explicit token is present, even if its value is empty.
    /// For the live environment, test the pointer without reading its bytes
    /// and before asking Foundation to copy the environment into strings.
    static func keychainEnvironment(_ environment: [String: String]?) -> [String: String]? {
        if environment == nil, getenv(oauthTokenKey) != nil { return nil }
        let environment = environment ?? ProcessInfo.processInfo.environment
        return environment.keys.contains(oauthTokenKey) ? nil : environment
    }

    /// How one of the variables is set, as Claude Code reads it.
    ///
    /// Claude Code can select different logins for different spellings of
    /// the same path, so keep the literal value rather than standardizing
    /// it. Any value that is set, even an empty one, counts.
    enum Setting: Sendable {
        /// Not set. For `CLAUDE_CONFIG_DIR`: `~/.claude` and the default
        /// Keychain item. For `CLAUDE_SECURESTORAGE_CONFIG_DIR`: the
        /// Keychain item follows `CLAUDE_CONFIG_DIR`.
        case implicit
        /// An absolute path, kept exactly as written.
        case absolute(String)
        /// Empty, `~`-prefixed or relative: Claude Code may resolve it
        /// against its own working directory, which differs between
        /// processes.
        case relative(String)

        init(_ environment: [String: String], key: String = ClaudeConfigProfile.environmentKey) {
            guard let literal = environment[key] else {
                self = .implicit
                return
            }
            self = literal.hasPrefix("/") ? .absolute(literal) : .relative(literal)
        }
    }

    /// The profile Claude Code uses with this environment and working
    /// directory. Recorded by the capture helper beside each snapshot.
    public static func identifier(
        environment: [String: String]? = nil,
        homeDirectory: URL,
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) -> String {
        guard let environment = keychainEnvironment(environment) else { return explicitOAuth }
        return profileIdentifier(environment, homeDirectory: homeDirectory, relativeTo: currentDirectory)
            ?? explicitOAuth
    }

    /// Relative paths cannot be reproduced by a CLI launched in an empty folder.
    static func verifiableIdentifier(environment: [String: String], homeDirectory: URL) -> String? {
        guard !environment.keys.contains(oauthTokenKey) else { return nil }
        return profileIdentifier(environment, homeDirectory: homeDirectory, relativeTo: nil)
    }

    private static func profileIdentifier(
        _ environment: [String: String], homeDirectory: URL, relativeTo currentDirectory: String?
    ) -> String? {
        let base: String
        switch Setting(environment) {
        case .implicit:
            base = defaultConfigIdentifier(homeDirectory: homeDirectory)
        case .absolute(let literal):
            base = "override:\(literal)"
        case .relative(let literal):
            guard let currentDirectory else { return nil }
            // Both the literal (Keychain item) and the folder it resolved to
            // (config files) identify the login.
            base = "relative:\(encode([literal, resolve(literal, in: currentDirectory)]))"
        }
        switch Setting(environment, key: secureStorageKey) {
        case .implicit:
            return base
        case .absolute(let literal):
            return "securestorage:\(encode([base, literal]))"
        case .relative(let literal):
            guard let currentDirectory else { return nil }
            return "relative-securestorage:\(encode([base, literal, resolve(literal, in: currentDirectory)]))"
        }
    }

    private static func defaultConfigIdentifier(homeDirectory: URL) -> String {
        homeDirectory.appendingPathComponent(".claude", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func resolve(_ literal: String, in currentDirectory: String) -> String {
        URL(fileURLWithPath: literal, relativeTo: URL(fileURLWithPath: currentDirectory, isDirectory: true))
            .standardizedFileURL.path
    }

    /// JSON keeps the parts unambiguous whatever characters they contain.
    private static func encode(_ parts: [String]) -> String {
        (try? JSONSerialization.data(withJSONObject: parts))
            .flatMap { String(data: $0, encoding: .utf8) } ?? parts.joined(separator: "\u{0}")
    }
}
