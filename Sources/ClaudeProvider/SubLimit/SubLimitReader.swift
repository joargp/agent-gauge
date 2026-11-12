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

    private let fetch: @Sendable () async -> Outcome
    private let now: @Sendable () -> Date
    private var cached: SubLimit?
    private var lastAttempt: Date?
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
    public func current(userInitiated: Bool) async -> SubLimit? {
        let moment = now()
        let interval = userInitiated ? Self.refreshInterval : Self.pollInterval
        let isDue = lastAttempt.map { moment.timeIntervalSince($0) >= interval } ?? true

        if inFlight == nil, isDue {
            lastAttempt = moment
            let fetch = fetch
            inFlight = Task { [weak self] in
                let outcome = await fetch()
                await self?.finish(outcome)
            }
        }
        if userInitiated, let inFlight {
            await inFlight.value
        }

        guard let cached, !cached.window.isRolledOver(now: now()) else { return nil }
        return cached
    }

    private func finish(_ outcome: Outcome) {
        switch outcome {
        case .found(let limit): cached = limit
        case .absent: cached = nil
        case .failed: break  // keep the last reading until its window resets
        }
        inFlight = nil
    }
}
