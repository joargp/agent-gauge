import Foundation
import GaugeCore

public enum ClaudeUsageError: Error, Equatable, Sendable {
    /// The cache file hasn't been written yet.
    case noCacheYet
    /// The cache file exists but couldn't be decoded.
    case invalidCache
    /// The cache file couldn't be read.
    case unreadableCache
    /// Settings action failed because a foreign statusLine is configured.
    case foreignStatusLine(command: String)
    /// A custom statusLine still references the capture helper and must be
    /// edited manually before uninstall can safely remove that helper.
    case integratedStatusLine(command: String)
    /// A statusLine value exists but isn't a supported command object.
    case malformedStatusLine
    /// Claude settings.json exists but isn't valid JSON.
    case invalidSettings
    /// Claude settings.json exists but couldn't be read.
    case unreadableSettings
    /// Claude settings.json is a symlink and must not be replaced atomically.
    case symlinkedSettings
    /// Claude settings changed outside Agent Gauge during a mutation.
    case concurrentSettingsChange
}

extension ClaudeUsageError {
    public var errorDescription: String? {
        switch self {
        case .noCacheYet:
            "No usage captured yet. Open a Claude Code session and send a message."
        case .invalidCache:
            "The usage cache is in an unexpected format."
        case .unreadableCache:
            "The usage cache couldn’t be read."
        case let .foreignStatusLine(command):
            "A different status line is configured (\"\(command)\"). Add a tee to claude-gauge-capture in it, or remove that statusLine entry."
        case let .integratedStatusLine(command):
            "The custom status line still references Agent Gauge (\"\(command)\"). Remove its claude-gauge capture segment, then uninstall again."
        case .malformedStatusLine:
            "The existing statusLine setting has an unsupported format and was left unchanged."
        case .invalidSettings:
            "~/.claude/settings.json isn’t valid JSON, so the status line couldn’t be registered."
        case .unreadableSettings:
            "~/.claude/settings.json exists but couldn’t be read, so it was left unchanged."
        case .symlinkedSettings:
            "~/.claude/settings.json is a symlink whose target couldn’t be resolved safely, so it was left unchanged."
        case .concurrentSettingsChange:
            "~/.claude/settings.json changed during setup and was left for you to review. Try again."
        }
    }
}

extension ClaudeUsageError: UsageError {
    /// A missing cache only means no capture has run yet.
    public var needsSetup: Bool {
        self == .noCacheYet
    }
}
