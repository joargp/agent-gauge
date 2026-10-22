import ClaudeProvider
import CodexProvider
import Foundation
import GaugeCore
import SwiftUI

/// Everything that differs between the agents Agent Gauge can show.
enum GaugeProvider: String, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    /// The agent's full name, where the popover header's short name is too
    /// terse.
    var productName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    var symbolName: String {
        switch self {
        case .claude: "sparkles"
        case .codex: "gauge.medium"
        }
    }

    var fiveHourTint: Color {
        switch self {
        case .claude: GaugePalette.claudeFiveHour
        case .codex: GaugePalette.codexFiveHour
        }
    }

    var weeklyTint: Color {
        switch self {
        case .claude: GaugePalette.claudeWeekly
        case .codex: GaugePalette.codexWeekly
        }
    }

    var accentTint: Color {
        switch self {
        case .claude: fiveHourTint
        case .codex: weeklyTint
        }
    }

    var privacyNote: String {
        switch self {
        case .claude: "No credentials. Reads a local cache written by your Claude status line."
        case .codex: "Uses your local Codex login. Credentials stay with Codex."
        }
    }

    /// Ring caption before the first reading.
    var awaitingCaption: String {
        switch self {
        case .claude: "Awaiting first capture"
        case .codex: "Waiting for Codex"
        }
    }

    /// Ring detail when a window has no current reading.
    var refreshHint: String {
        switch self {
        case .claude: "Start Claude Code to refresh"
        case .codex: "Refresh to update"
        }
    }

    /// Shown after the data age once a reading is stale.
    var staleHint: String {
        switch self {
        case .claude: "start Claude Code to refresh"
        case .codex: "Codex isn’t responding"
        }
    }

    /// Claude only updates while a session renders its status line, so its
    /// age reads as a capture. Codex is polled, so its age reads as an update.
    var describesAgeAsCapture: Bool {
        self == .claude
    }

    var refreshInterval: TimeInterval {
        switch self {
        case .claude: 10
        case .codex: 60
        }
    }

    func makeUsageProvider() -> any UsageProvider {
        switch self {
        case .claude: ClaudeUsageProvider()
        case .codex: CodexAppServerClient()
        }
    }
}
