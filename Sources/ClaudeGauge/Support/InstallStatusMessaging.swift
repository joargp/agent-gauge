import Foundation
import ClaudeGaugeCore

extension StatuslineInstallStatus {
    /// A human-facing hint about what's missing, or nil when everything is
    /// in place.
    var guidanceMessage: String? {
        switch state {
        case .missing:
            if captureBinaryExists {
                "Status line not registered. Run: ~/.claude/claude-gauge/capture install-statusline"
            } else {
                "Not installed. Run ./script/install.sh from the claude-gauge repo."
            }
        case let .foreign(command):
            "Another status line is configured (\"\(command)\"). Prefix it with `tee >(~/.claude/claude-gauge/capture >/dev/null) |` to feed Claude Gauge."
        case .installed, .integrated:
            if !captureBinaryExists {
                "Capture binary missing. Re-run ./script/install.sh."
            } else if !cacheFileExists {
                "Waiting for the first capture. Open a Claude Code session and send a message."
            } else {
                nil
            }
        case .malformed:
            "The existing statusLine setting has an unsupported format and was left unchanged."
        case .unreadable:
            "~/.claude/settings.json couldn’t be read and was left unchanged."
        }
    }
}
