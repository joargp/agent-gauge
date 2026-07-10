import Foundation
import XCTest
@testable import CodexGauge

@MainActor
final class UsageStoreTests: XCTestCase {
    func testRefreshPublishesUsage() async {
        let snapshot = sampleSnapshot()
        let store = UsageStore(client: SequenceFetcher([.success(snapshot)]))

        await store.refresh()

        XCTAssertEqual(store.usage, snapshot)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isRefreshing)
    }

    func testTransientFailurePreservesLastSuccessfulUsage() async {
        let snapshot = sampleSnapshot()
        let store = UsageStore(client: SequenceFetcher([
            .success(snapshot),
            .failure(.timedOut)
        ]))

        await store.refresh()
        await store.refresh()

        XCTAssertEqual(store.usage, snapshot)
        XCTAssertEqual(store.errorMessage, CodexUsageError.timedOut.errorDescription)
    }

    func testStartRefreshesAutomatically() async throws {
        let fetcher = CountingFetcher(snapshot: sampleSnapshot())
        let store = UsageStore(client: fetcher, refreshInterval: 0.02)
        store.start()
        defer { store.stop() }

        for _ in 0..<100 {
            if await fetcher.callCount >= 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        let callCount = await fetcher.callCount
        XCTAssertGreaterThanOrEqual(callCount, 2)
    }

    private func sampleSnapshot() -> CodexUsageSnapshot {
        CodexUsageSnapshot(
            primary: UsageWindow(usedPercent: 10, windowDurationMins: 300, resetsAt: nil),
            secondary: UsageWindow(usedPercent: 20, windowDurationMins: 10_080, resetsAt: nil),
            planType: "pro",
            fetchedAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}

private actor CountingFetcher: CodexUsageFetching {
    private(set) var callCount = 0
    private let snapshot: CodexUsageSnapshot

    init(snapshot: CodexUsageSnapshot) {
        self.snapshot = snapshot
    }

    func fetchUsage() async throws -> CodexUsageSnapshot {
        callCount += 1
        return snapshot
    }
}

private actor SequenceFetcher: CodexUsageFetching {
    enum Outcome: Sendable {
        case success(CodexUsageSnapshot)
        case failure(CodexUsageError)
    }

    private var outcomes: [Outcome]

    init(_ outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func fetchUsage() async throws -> CodexUsageSnapshot {
        guard !outcomes.isEmpty else { throw CodexUsageError.usageUnavailable }
        switch outcomes.removeFirst() {
        case let .success(snapshot):
            return snapshot
        case let .failure(error):
            throw error
        }
    }
}
