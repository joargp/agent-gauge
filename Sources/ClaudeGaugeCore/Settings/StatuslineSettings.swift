import Foundation

public enum StatuslineChange: Equatable, Sendable {
    case installed
    case updated
    case alreadyInstalled
    case removed
    case alreadyAbsent
}

/// Result of inspecting ~/.claude/settings.json plus the capture install
/// directory.
public struct StatuslineInstallStatus: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// A statusLine whose command belongs to Claude Gauge.
        case installed(command: String)
        /// A custom statusLine command that also tees stdin into Claude Gauge.
        /// It is recognized as working but never rewritten or removed.
        case integrated(command: String)
        /// No statusLine configured.
        case missing
        /// A statusLine configured by something else.
        case foreign(command: String)
        /// A statusLine value exists but isn't a supported command object.
        case malformed
        /// settings.json exists but isn't valid JSON.
        case unreadable
    }

    public let state: State
    public let captureBinaryExists: Bool
    public let cacheFileExists: Bool

    public init(
        state: State,
        captureBinaryExists: Bool,
        cacheFileExists: Bool
    ) {
        self.state = state
        self.captureBinaryExists = captureBinaryExists
        self.cacheFileExists = cacheFileExists
    }
}

/// Pure mutations of Claude Code user settings JSON, kept free of file I/O
/// so they can be tested exhaustively.
public enum StatuslineSettings {
    public static func inspect(settingsJSON: Data?, capturePath: String) -> StatuslineInstallStatus.State {
        guard let settingsJSON else { return .missing }
        guard let object = try? decodeObject(settingsJSON) else { return .unreadable }
        return state(of: object, capturePath: capturePath)
    }

    public static func apply(settingsJSON: Data?, capturePath: String) throws -> (data: Data, change: StatuslineChange) {
        var object = try decodeObject(settingsJSON)

        switch state(of: object, capturePath: capturePath) {
        case let .foreign(command):
            throw ClaudeUsageError.foreignStatusLine(command: command)
        case .integrated:
            return (try encode(object), .alreadyInstalled)
        case let .installed(command) where command == capturePath:
            return (try encode(object), .alreadyInstalled)
        case .installed:
            object["statusLine"] = ["type": "command", "command": capturePath]
            return (try encode(object), .updated)
        case .malformed:
            throw ClaudeUsageError.malformedStatusLine
        case .missing, .unreadable:
            object["statusLine"] = ["type": "command", "command": capturePath]
            return (try encode(object), .installed)
        }
    }

    public static func remove(
        settingsJSON: Data?,
        capturePath: String
    ) throws -> (data: Data, change: StatuslineChange) {
        var object = try decodeObject(settingsJSON)

        switch state(of: object, capturePath: capturePath) {
        case .installed:
            object.removeValue(forKey: "statusLine")
            return (try encode(object), .removed)
        case let .integrated(command):
            throw ClaudeUsageError.integratedStatusLine(command: command)
        case .malformed:
            throw ClaudeUsageError.malformedStatusLine
        case let .foreign(command):
            // Unknown status-line commands may reference the helper through
            // variables, relative paths, or wrapper scripts. Fail closed so
            // uninstall never deletes a potentially referenced executable.
            throw ClaudeUsageError.foreignStatusLine(command: command)
        case .missing, .unreadable:
            return (try encode(object), .alreadyAbsent)
        }
    }

    static func decodeObject(_ data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }
        guard !data.isEmpty else { throw ClaudeUsageError.invalidSettings }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ClaudeUsageError.invalidSettings
        }
        return object
    }

    static func encode(_ object: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        data.append(0x0A)
        return data
    }

    private static func state(
        of object: [String: Any],
        capturePath: String
    ) -> StatuslineInstallStatus.State {
        guard let rawEntry = object["statusLine"] else {
            return .missing
        }
        guard let entry = rawEntry as? [String: Any],
              let type = entry["type"] as? String,
              type == "command",
              let command = entry["command"] as? String,
              !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .malformed
        }

        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == capturePath {
            return .installed(command: command)
        }
        if trimmed.contains(capturePath)
            || trimmed.contains("~/.claude/claude-gauge/capture")
        {
            return .integrated(command: command)
        }
        return .foreign(command: command)
    }
}
