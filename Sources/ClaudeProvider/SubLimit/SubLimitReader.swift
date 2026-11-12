import Foundation
import GaugeCore

/// Reads Claude's optional Fable limit through the Claude CLI, rarely and
/// never concurrently. Failures never surface: the limit is just absent.
public actor SubLimitReader {
    public enum Outcome: Sendable {
        case found(SubLimit)
        /// The CLI ran but reported no Fable limit.
        case absent
        case failed
    }

    public static let pollInterval: TimeInterval = 300
    public static let refreshInterval: TimeInterval = 60
    /// A reading is dropped once reads have kept failing for this long, so a
    /// frozen value never sits under a fresh "Updated" line.
    public static let staleAfterFailures: TimeInterval = 1800

    private let fetch: @Sendable () async -> Outcome
    private let now: @Sendable () -> Date
    private var cached: SubLimit?
    private var lastAttempt: Date?
    private var lastSuccess: Date?
    private var lastAttemptFailed = false
    /// The status line capture time the last background run was started for.
    private var lastPolledCapture: Date?
    private var inFlight: Task<Void, Never>?

    public init() {
        let command = ClaudeUsageCommand()
        self.init(fetch: { await command.fetch() }, now: { Date() })
    }

    init(
        fetch: @escaping @Sendable () async -> Outcome,
        now: @escaping @Sendable () -> Date
    ) {
        self.fetch = fetch
        self.now = now
    }

    /// The last known limit. Starts a CLI run when one is due: every five
    /// minutes, or once a minute when the user asked for a refresh. A
    /// user-initiated call waits for the run; others return at once.
    ///
    /// Each run starts the whole Claude CLI, so background runs also wait for
    /// Claude Code to capture new usage (`capturedAt` moving on). While Claude
    /// Code is idle on this Mac, only Refresh reads the limit again.
    public func current(userInitiated: Bool, capturedAt: Date? = nil) async -> SubLimit? {
        let moment = now()
        let interval = userInitiated ? Self.refreshInterval : Self.pollInterval
        let isDue = lastAttempt.map { moment.timeIntervalSince($0) >= interval } ?? true
        let hasNewActivity = userInitiated || capturedAt == nil || capturedAt != lastPolledCapture

        if inFlight == nil, isDue, hasNewActivity {
            lastAttempt = moment
            lastPolledCapture = capturedAt
            let fetch = fetch
            inFlight = Task { [weak self] in
                let outcome = await fetch()
                await self?.finish(outcome)
            }
        }
        if userInitiated, let inFlight {
            await inFlight.value
        }

        let current = now()
        guard let cached, !cached.window.isRolledOver(now: current) else { return nil }
        if lastAttemptFailed, let lastSuccess,
           current.timeIntervalSince(lastSuccess) >= Self.staleAfterFailures
        {
            return nil
        }
        return cached
    }

    private func finish(_ outcome: Outcome) {
        switch outcome {
        case .found(let limit):
            cached = limit
            lastSuccess = now()
            lastAttemptFailed = false
        case .absent:
            cached = nil
            lastAttemptFailed = false
        case .failed:
            // Keep the last reading for a while; one slow run shouldn't hide it.
            lastAttemptFailed = true
        }
        inFlight = nil
    }
}
