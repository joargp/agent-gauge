import Foundation
import XCTest
@testable import AgentGauge
import GaugeCore

@MainActor
final class UsageStoreTests: XCTestCase {
    func testRefreshPublishesUsageAndSetupGuidance() async {
        let snapshot = sampleSnapshot()
        let store = UsageStore(
            provider: SequenceProvider([.success(snapshot)], guidance: "Finish setup"),
            refreshInterval: 60
        )

        await store.refresh()

        XCTAssertEqual(store.usage, snapshot)
        XCTAssertEqual(store.setupMessage, "Finish setup")
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isRefreshing)
    }

    func testSetupErrorIsGuidanceNotError() async {
        let store = UsageStore(
            provider: SequenceProvider([.failure(.notSetUp)]),
            refreshInterval: 60
        )

        await store.refresh()

        XCTAssertNil(store.usage)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.setupMessage, FakeUsageError.notSetUp.errorDescription)
    }

    func testProviderGuidanceTakesPriorityOverSetupError() async {
        let store = UsageStore(
            provider: SequenceProvider([.failure(.notSetUp)], guidance: "Install the helper"),
            refreshInterval: 60
        )

        await store.refresh()

        XCTAssertEqual(store.setupMessage, "Install the helper")
        XCTAssertNil(store.errorMessage)
    }

    func testTransientFailurePreservesLastSuccessfulUsage() async {
        let snapshot = sampleSnapshot()
        let store = UsageStore(
            provider: SequenceProvider([.success(snapshot), .failure(.broken)]),
            refreshInterval: 60
        )

        await store.refresh()
        await store.refresh()

        XCTAssertEqual(store.usage, snapshot)
        XCTAssertEqual(store.errorMessage, FakeUsageError.broken.errorDescription)
        XCTAssertNil(store.setupMessage)
    }

    func testStartRefreshesAutomatically() async throws {
        let provider = CountingProvider(snapshot: sampleSnapshot())
        let store = UsageStore(provider: provider, refreshInterval: 0.02)
        store.start()
        defer { store.stop() }

        for _ in 0..<100 {
            if await provider.callCount >= 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        let callCount = await provider.callCount
        XCTAssertGreaterThanOrEqual(callCount, 2)
    }

    func testStopEndsRefreshing() async throws {
        let provider = CountingProvider(snapshot: sampleSnapshot())
        let store = UsageStore(provider: provider, refreshInterval: 0.01)
        store.start()
        for _ in 0..<100 {
            if await provider.callCount >= 1 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        store.stop()
        XCTAssertFalse(store.isRunning)

        try await Task.sleep(for: .milliseconds(30))
        let countAfterStop = await provider.callCount
        try await Task.sleep(for: .milliseconds(50))
        let laterCount = await provider.callCount
        XCTAssertEqual(laterCount, countAfterStop)
    }

    func testRefreshLoopDoesNotRetainStoreWhileSleeping() async throws {
        let provider = CountingProvider(snapshot: sampleSnapshot())
        weak var weakStore: UsageStore?

        do {
            let store = UsageStore(provider: provider, refreshInterval: 60)
            weakStore = store
            store.start()
            for _ in 0..<100 {
                if await provider.callCount >= 1 { break }
                try await Task.sleep(for: .milliseconds(1))
            }
        }

        for _ in 0..<100 where weakStore != nil {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertNil(weakStore)
    }

    private func sampleSnapshot() -> UsageSnapshot {
        UsageSnapshot(
            fiveHourWindow: UsageWindow(usedPercent: 10, resetsAt: nil),
            weeklyWindow: UsageWindow(usedPercent: 20, resetsAt: nil),
            badge: "Pro",
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}

enum FakeUsageError: UsageError, Equatable {
    case notSetUp
    case broken

    var needsSetup: Bool {
        self == .notSetUp
    }

    var errorDescription: String? {
        switch self {
        case .notSetUp: "Sign in first."
        case .broken: "Something broke."
        }
    }
}

actor CountingProvider: UsageProvider {
    private(set) var callCount = 0
    private let snapshot: UsageSnapshot

    init(snapshot: UsageSnapshot) {
        self.snapshot = snapshot
    }

    func readUsage() async throws -> UsageSnapshot {
        callCount += 1
        return snapshot
    }

    func setupGuidance() async -> String? {
        nil
    }
}

private actor SequenceProvider: UsageProvider {
    enum Outcome: Sendable {
        case success(UsageSnapshot)
        case failure(FakeUsageError)
    }

    private var outcomes: [Outcome]
    private let guidance: String?

    init(_ outcomes: [Outcome], guidance: String? = nil) {
        self.outcomes = outcomes
        self.guidance = guidance
    }

    func readUsage() async throws -> UsageSnapshot {
        guard !outcomes.isEmpty else { throw FakeUsageError.broken }
        switch outcomes.removeFirst() {
        case let .success(snapshot):
            return snapshot
        case let .failure(error):
            throw error
        }
    }

    func setupGuidance() async -> String? {
        guidance
    }
}
