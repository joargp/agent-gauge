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
    static let explicitOAuth = "explicit-oauth"

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
        let config = Setting(environment)
        let base: String
        if case .relative(let literal) = config {
            // Both the literal (Keychain item) and the folder it resolved to
            // (config files) identify the login.
            base = "relative:\(encode([literal, resolve(literal, in: currentDirectory)]))"
        } else {
            base = verifiableConfigIdentifier(config, homeDirectory: homeDirectory) ?? ""
        }
        switch Setting(environment, key: secureStorageKey) {
        case .implicit, .absolute:
            return secureStorageIdentifier(base: base, environment: environment) ?? base
        case .relative(let literal):
            // Never equal to an identifier the app can verify (see below).
            return "relative-securestorage:\(encode([base, literal, resolve(literal, in: currentDirectory)]))"
        }
    }

    /// The identifier Agent Gauge can check with its own `/usage` run, or
    /// nil with an explicit token or a relative override. The CLI runs in
    /// an empty folder of its own, so it could only reach a relative profile
    /// by changing the literal value and thus the login.
    static func verifiableIdentifier(environment: [String: String], homeDirectory: URL) -> String? {
        guard !environment.keys.contains(oauthTokenKey),
              let base = verifiableConfigIdentifier(Setting(environment), homeDirectory: homeDirectory)
        else { return nil }
        return secureStorageIdentifier(base: base, environment: environment)
    }

    /// Adds an absolute `CLAUDE_SECURESTORAGE_CONFIG_DIR`, exactly as
    /// written, to `base`. Nil for a relative or empty one. Unset keeps
    /// `base` unchanged, so caches from before this variable was recorded
    /// still match.
    private static func secureStorageIdentifier(base: String, environment: [String: String]) -> String? {
        switch Setting(environment, key: secureStorageKey) {
        case .implicit:
            return base
        case .absolute(let literal):
            return "securestorage:\(encode([base, literal]))"
        case .relative:
            return nil
        }
    }

    private static func verifiableConfigIdentifier(_ setting: Setting, homeDirectory: URL) -> String? {
        switch setting {
        case .implicit:
            return homeDirectory.appendingPathComponent(".claude", isDirectory: true)
                .standardizedFileURL.resolvingSymlinksInPath().path
        case .absolute(let literal):
            // Explicit, even when it names the default folder: Claude Code
            // then uses a different Keychain item.
            return "override:\(literal)"
        case .relative:
            return nil
        }
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
