import Foundation
import GaugeCore

/// Reads Claude's weekly limits through one shared, throttled CLI call.
public actor SubLimitReader {
    public enum Outcome: Sendable {
        case found(SubLimit)
        case reading(weekly: UsageWindow, fable: SubLimit?)
        /// The CLI ran but reported no Fable limit.
        case absent
        case failed
    }

    /// Background runs only keep the value warm for the popover, which reads
    /// it again when opened, so they can be rare.
    public static let pollInterval: TimeInterval = 900
    public static let refreshInterval: TimeInterval = 60
    /// A reading is dropped once reads have kept failing for this long, so a
    /// frozen value never sits under a fresh "Updated" line.
    public static let staleAfterFailures: TimeInterval = 1800

    /// What the latest check found, and which status-line readings it
    /// settled.
    struct Reading: Sendable {
        var fable: SubLimit?
        var weekly: UsageWindow?
        var checkedAt: Date?
        /// When the check that produced `weekly` started.
        var checkStartedAt: Date?
        let evaluatedAt: Date
        var verificationFailed: Bool
        /// Status-line weekly readings a successful check contradicted. An
        /// idle session redraws these with new capture times, so a newer
        /// capture time alone does not make them new information. They stay
        /// rejected through failed or incomplete checks and after the
        /// verified value expires, until a check confirms them or their own
        /// window ends. The dates are the reset (or an estimated deadline
        /// when a status-line reading has no reset time).
        var rejectedStatuslineWeeklies: [UsageWindow: Date] = [:]

        /// Capture time alone cannot make a contradicted redraw trustworthy.
        /// While checks fail, a reading that no check contradicted wins if
        /// it may be newer than the check's evidence. The CLI fetched that
        /// evidence at some unknown moment while it ran, so this covers any
        /// reading that may have been captured after the check started (its
        /// rounded capture time leaves that open), not only after it ended.
        func verifiedWeekly(over statusline: UsageWindow?, capturedAt: Date?) -> (UsageWindow, Date)? {
            guard let weekly, let checkedAt else { return nil }
            if verificationFailed, let statusline, !statusline.isRolledOver(now: evaluatedAt),
               let capturedAt, let checkStartedAt,
               SubLimitReader.mayHaveBeenCaptured(at: capturedAt, after: checkStartedAt),
               !rejects(statusline) {
                return nil
            }
            return (weekly, checkedAt)
        }

        /// True when a check showed this exact status-line reading is wrong.
        func rejects(_ statusline: UsageWindow) -> Bool {
            rejectedStatuslineWeeklies[statusline] != nil
        }
    }

    /// Without a reset time, keep a rejection for one full weekly window
    /// from the check that contradicted it. A redraw alone cannot renew it.
    private static let resetlessRejectionLifetime: TimeInterval = 7 * 24 * 60 * 60

    /// The Claude config folder whose login the CLI reports on. Nil when it
    /// is unknown, so no status-line reading can be matched to it.
    nonisolated let configProfile: String?
    private let fetch: @Sendable () async -> Outcome
    private let now: @Sendable () -> Date
    private var cached: SubLimit?
    private var weekly: UsageWindow?
    /// When the check that produced `weekly` ran. Its evidence is from
    /// some moment within this range.
    private var weeklyCheckedDuring: ClosedRange<Date>?
    private var lastAttempt: Date?
    private var lastSuccess: Date?
    private var lastAttemptFailed = false
    /// The status line capture time the last background run was started for.
    private var lastPolledCapture: Date?
    private var rejectedStatuslineWeeklies: [UsageWindow: Date] = [:]
    private var inFlight: Task<Void, Never>?

    public init() {
        let command = ClaudeUsageCommand()
        self.init(
            configProfile: command.configProfile,
            fetch: { await command.fetchUsage() },
            now: { Date() }
        )
    }

    init(
        configProfile: String? = nil,
        fetch: @escaping @Sendable () async -> Outcome,
        now: @escaping @Sendable () -> Date
    ) {
        self.configProfile = configProfile
        self.fetch = fetch
        self.now = now
    }

    /// The last known Fable limit. User-initiated calls wait for an in-flight
    /// CLI run; background calls return the cached reading immediately.
    ///
    /// Each run starts the whole Claude CLI, so background runs also wait for
    /// Claude Code to capture new usage (`capturedAt` moving on). While Claude
    /// Code is idle on this Mac, only Refresh reads the limit again.
    public func current(userInitiated: Bool, capturedAt: Date? = nil) async -> SubLimit? {
        await currentReading(userInitiated: userInitiated, capturedAt: capturedAt).fable
    }

    /// `statuslineWeekly` must come from the same Claude profile as the CLI,
    /// or be nil: a reading from another login is not something to verify.
    func currentReading(
        userInitiated: Bool,
        capturedAt: Date?,
        statuslineWeekly: UsageWindow? = nil
    ) async -> Reading {
        let moment = now()
        let shown = makeReading(at: moment)
        let needsVerification = statuslineWeekly.map {
            !shown.rejects($0) && disagrees($0, at: moment)
        } ?? false
        let rolledOver = weekly?.isRolledOver(now: moment) ?? false
        // A contradicted status-line reading with no checked value to show
        // in its place leaves the weekly limit unavailable, for example
        // after `/usage` printed no all-models row.
        let needsRecovery = statuslineWeekly.map { shown.weekly == nil && shown.rejects($0) } ?? false
        let isUrgent = userInitiated || needsVerification || rolledOver || needsRecovery
        let interval = isUrgent ? Self.refreshInterval : Self.pollInterval
        let isDue = lastAttempt.map { moment.timeIntervalSince($0) >= interval } ?? true
        let hasNewActivity = userInitiated || capturedAt == nil || capturedAt != lastPolledCapture

        if inFlight == nil, isDue, hasNewActivity {
            lastAttempt = moment
            lastPolledCapture = capturedAt
            let fetch = fetch
            inFlight = Task { [weak self] in
                let outcome = await fetch()
                await self?.finish(outcome, startedAt: moment, statuslineWeekly: statuslineWeekly)
            }
        }
        if userInitiated, let inFlight {
            await inFlight.value
        }

        return makeReading(at: now())
    }

    /// Capture times are rounded down, so a reading's capture happened
    /// somewhere in its rounding step, `[capturedAt, capturedAt + step)`. Only
    /// a step that ends by `instant` proves the capture came first.
    static func mayHaveBeenCaptured(at capturedAt: Date, after instant: Date) -> Bool {
        capturedAt.addingTimeInterval(CaptureRunner.capturedAtRounding) > instant
    }

    /// Settles a same-profile status-line weekly reading read after a check,
    /// which may have been written while the check ran, and returns the
    /// state to display. It runs in one actor step, so the evidence it is
    /// judged against cannot change halfway.
    ///
    /// A check only contradicts a reading it provably came after. The CLI
    /// asks Anthropic for usage at some moment between the check's start
    /// and end that cannot be observed from here, and a status-line
    /// reading may report a newer server value than the one the CLI got,
    /// higher or lower, since a lower one may be a correction. So only a
    /// reading whose whole rounding step ends by the check's start is
    /// older than the check's evidence, and any material difference
    /// rejects it. A reading that may have been captured after the check
    /// started is never rejected by it, even when it shows less usage. An
    /// idle session redrawing an old value at that moment is therefore not
    /// caught by this check, only by the next one, which reads it before
    /// starting. A reading with no capture time has no established order
    /// and is not rejected either.
    func reconcile(statuslineWeekly: UsageWindow?, capturedAt: Date?) -> Reading {
        let current = now()
        if let statuslineWeekly, let capturedAt, let checkedDuring = weeklyCheckedDuring,
           disagrees(statuslineWeekly, at: current),
           !Self.mayHaveBeenCaptured(at: capturedAt, after: checkedDuring.lowerBound)
        {
            reject(statuslineWeekly, checkedAt: checkedDuring.upperBound)
        }
        return makeReading(at: current)
    }

    private func makeReading(at current: Date) -> Reading {
        for (reading, deadline) in rejectedStatuslineWeeklies where deadline <= current {
            rejectedStatuslineWeeklies.removeValue(forKey: reading)
        }
        if lastAttemptFailed, let lastSuccess,
           current.timeIntervalSince(lastSuccess) >= Self.staleAfterFailures
        {
            return Reading(
                evaluatedAt: current,
                verificationFailed: true,
                rejectedStatuslineWeeklies: rejectedStatuslineWeeklies
            )
        }
        return Reading(
            fable: cached.flatMap { $0.window.isRolledOver(now: current) ? nil : $0 },
            weekly: currentWeekly(at: current),
            checkedAt: lastSuccess,
            checkStartedAt: weeklyCheckedDuring?.lowerBound,
            evaluatedAt: current,
            verificationFailed: lastAttemptFailed,
            rejectedStatuslineWeeklies: rejectedStatuslineWeeklies
        )
    }

    /// The status-line and `/usage` reset times may differ by rounding.
    private static let resetTolerance: TimeInterval = 60

    private func currentWeekly(at current: Date) -> UsageWindow? {
        guard weeklyCheckedDuring != nil, let weekly, !weekly.isRolledOver(now: current) else { return nil }
        return weekly
    }

    /// Only current rows can disagree. The helper may preserve an expired
    /// status-line row even after a successful new-week check.
    private func disagrees(_ statusline: UsageWindow, at current: Date) -> Bool {
        guard let weekly = currentWeekly(at: current), !statusline.isRolledOver(now: current)
        else { return false }
        let differentReset = statusline.resetsAt.map { statusReset in
            weekly.resetsAt.map { abs($0.timeIntervalSince(statusReset)) > Self.resetTolerance } ?? false
        } ?? false
        return differentReset || abs(weekly.usedPercent - statusline.usedPercent) >= 1
    }

    private func reject(_ statusline: UsageWindow, checkedAt: Date) {
        let deadline = statusline.resetsAt ?? checkedAt.addingTimeInterval(Self.resetlessRejectionLifetime)
        if rejectedStatuslineWeeklies[statusline].map({ $0 >= deadline }) != true {
            rejectedStatuslineWeeklies[statusline] = deadline
        }
    }

    private func finish(_ outcome: Outcome, startedAt: Date, statuslineWeekly: UsageWindow?) {
        switch outcome {
        case .reading(let weekly, let fable):
            let finishedAt = now()
            self.weekly = weekly
            cached = fable
            lastSuccess = finishedAt
            lastAttemptFailed = false
            // A row from a week that ended by completion is only a rollover
            // marker for retries, not evidence for or against any fallback.
            weeklyCheckedDuring = nil
            guard !weekly.isRolledOver(now: finishedAt) else { break }
            let checkedAt = max(startedAt, finishedAt)
            weeklyCheckedDuring = startedAt...checkedAt
            // A reading the CLI now confirms is no longer contradicted.
            for reading in rejectedStatuslineWeeklies.keys where !disagrees(reading, at: finishedAt) {
                rejectedStatuslineWeeklies.removeValue(forKey: reading)
            }
            // This reading was read before the check started, so it is
            // known to be older than the CLI's value.
            if let statuslineWeekly, disagrees(statuslineWeekly, at: finishedAt) {
                reject(statuslineWeekly, checkedAt: checkedAt)
            }
        // Without an all-models row there is no verified weekly value, but
        // earlier rejections stay: the readings they cover are still wrong.
        case .found(let limit):
            weekly = nil
            weeklyCheckedDuring = nil
            cached = limit
            lastSuccess = now()
            lastAttemptFailed = false
        case .absent:
            weekly = nil
            weeklyCheckedDuring = nil
            cached = nil
            lastAttemptFailed = false
        case .failed:
            // Keep the last reading for a while; one slow run shouldn't hide it.
            lastAttemptFailed = true
        }
        inFlight = nil
    }
}
