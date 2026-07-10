import Foundation

enum CodexUsageError: Error, Equatable, Sendable {
    case executableNotFound
    case launchFailed
    case timedOut
    case serverExited(Int32)
    case notLoggedIn
    case serverError(Int?)
    case invalidResponse
    case usageUnavailable
}

extension CodexUsageError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Codex CLI wasn’t found. Install Codex or set CODEX_GAUGE_CODEX_PATH."
        case .launchFailed:
            "Codex app-server could not be started."
        case .timedOut:
            "Codex took too long to return usage."
        case let .serverExited(status):
            "Codex app-server exited unexpectedly (status \(status))."
        case .notLoggedIn:
            "Codex isn’t signed in with ChatGPT. Run codex login, then refresh."
        case let .serverError(code):
            if let code {
                "Codex could not return usage (error \(code))."
            } else {
                "Codex could not return usage."
            }
        case .invalidResponse:
            "Codex returned usage in an unexpected format."
        case .usageUnavailable:
            "No 5-hour or weekly usage windows were returned."
        }
    }
}
