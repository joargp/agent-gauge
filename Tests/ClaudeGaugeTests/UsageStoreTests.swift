import Foundation
import XCTest
@testable import ClaudeGauge
@testable import ClaudeGaugeCore

@MainActor
final class UsageStoreTests: XCTestCase {
    func testRefreshPublishesUsageAndStatus() async {
        let snapshot = sampleSnapshot()
        let status = installedStatus()
        let store = UsageStore(reader: SequenceReader(
            outcomes: [.success(snapshot)],
            status: status
        ))

        await store.refresh()

        XCTAssertEqual(store.usage, snapshot)
        XCTAssertEqual(store.installStatus, status)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isRefreshing)
    }

    func testNoCacheYetIsWaitingStateNotError() async {
        let store = UsageStore(reader: SequenceReader(
            outcomes: [.failure(.noCacheYet)],
            status: installedStatus(cacheFileExists: false)
        ))

        await store.refresh()

        XCTAssertNil(store.usage)
        XCTAssertNil(store.errorMessage)
    }

    func testTransientFailurePreservesLastSuccessfulUsage() async {
        let snapshot = sampleSnapshot()
        let store = UsageStore(reader: SequenceReader(
            outcomes: [
                .success(snapshot),
                .failure(.invalidCache)
            ],
            status: installedStatus()
        ))

        await store.refresh()
        await store.refresh()

        XCTAssertEqual(store.usage, snapshot)
        XCTAssertEqual(store.errorMessage, ClaudeUsageError.invalidCache.errorDescription)
    }

    func testStartRefreshesAutomatically() async throws {
        let reader = CountingReader(snapshot: sampleSnapshot())
        let store = UsageStore(reader: reader, refreshInterval: 0.02)
        store.start()
        defer { store.stop() }

        for _ in 0..<100 {
            if await reader.callCount >= 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        let callCount = await reader.callCount
        XCTAssertGreaterThanOrEqual(callCount, 2)
    }

    func testRefreshLoopDoesNotRetainStoreWhileSleeping() async throws {
        let reader = CountingReader(snapshot: sampleSnapshot())
        weak var weakStore: UsageStore?

        do {
            let store = UsageStore(reader: reader, refreshInterval: 60)
            weakStore = store
            store.start()
            for _ in 0..<100 {
                if await reader.callCount >= 1 { break }
                try await Task.sleep(for: .milliseconds(1))
            }
        }

        for _ in 0..<100 where weakStore != nil {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertNil(weakStore)
    }

    private func sampleSnapshot() -> ClaudeUsageSnapshot {
        ClaudeUsageSnapshot(
            fiveHourWindow: UsageWindow(usedPercent: 10, resetsAt: nil),
            sevenDayWindow: UsageWindow(usedPercent: 20, resetsAt: nil),
            claudeCodeVersion: "2.1.250",
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func installedStatus(cacheFileExists: Bool = true) -> StatuslineInstallStatus {
        StatuslineInstallStatus(
            state: .installed(command: "/tmp/claude-gauge/capture"),
            captureBinaryExists: true,
            cacheFileExists: cacheFileExists
        )
    }
}

private actor CountingReader: UsageReading {
    private(set) var callCount = 0
    private let snapshot: ClaudeUsageSnapshot

    init(snapshot: ClaudeUsageSnapshot) {
        self.snapshot = snapshot
    }

    func readUsage() async throws -> ClaudeUsageSnapshot {
        callCount += 1
        return snapshot
    }

    func readInstallStatus() async -> StatuslineInstallStatus {
        StatuslineInstallStatus(
            state: .installed(command: "/tmp/claude-gauge/capture"),
            captureBinaryExists: true,
            cacheFileExists: true
        )
    }
}

private actor SequenceReader: UsageReading {
    enum Outcome: Sendable {
        case success(ClaudeUsageSnapshot)
        case failure(ClaudeUsageError)
    }

    private var outcomes: [Outcome]
    private let status: StatuslineInstallStatus

    init(outcomes: [Outcome], status: StatuslineInstallStatus) {
        self.outcomes = outcomes
        self.status = status
    }

    func readUsage() async throws -> ClaudeUsageSnapshot {
        guard !outcomes.isEmpty else { throw ClaudeUsageError.noCacheYet }
        switch outcomes.removeFirst() {
        case let .success(snapshot):
            return snapshot
        case let .failure(error):
            throw error
        }
    }

    func readInstallStatus() async -> StatuslineInstallStatus {
        status
    }
}
