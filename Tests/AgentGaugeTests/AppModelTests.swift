import Foundation
import XCTest
@testable import AgentGauge
import GaugeCore

@MainActor
final class AppModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AppModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testShowsAllProvidersByDefaultAndStartsTheirStores() {
        let model = makeModel()

        XCTAssertEqual(model.visibleProviders, Set(GaugeProvider.allCases))
        XCTAssertTrue(model.store(for: .claude).isRunning)
        XCTAssertTrue(model.store(for: .codex).isRunning)
    }

    func testHidingProviderStopsItsStoreAndPersists() {
        let model = makeModel()

        model.setVisible(false, for: .codex)

        XCTAssertFalse(model.isVisible(.codex))
        XCTAssertFalse(model.store(for: .codex).isRunning)
        XCTAssertTrue(model.store(for: .claude).isRunning)

        let reloaded = makeModel()
        XCTAssertEqual(reloaded.visibleProviders, [.claude])
        XCTAssertFalse(reloaded.store(for: .codex).isRunning)
    }

    func testShowingProviderStartsItsStore() {
        let model = makeModel()
        model.setVisible(false, for: .codex)

        model.setVisible(true, for: .codex)

        XCTAssertTrue(model.isVisible(.codex))
        XCTAssertTrue(model.store(for: .codex).isRunning)
    }

    func testLastVisibleProviderCannotBeHidden() {
        let model = makeModel()
        model.setVisible(false, for: .codex)

        XCTAssertFalse(model.canHide(.claude))
        model.setVisible(false, for: .claude)

        XCTAssertEqual(model.visibleProviders, [.claude])
        XCTAssertTrue(model.store(for: .claude).isRunning)
    }

    func testRecoversWhenStoredSettingsHideEverything() {
        for provider in GaugeProvider.allCases {
            defaults.set(false, forKey: "show.\(provider.rawValue)")
        }

        let model = makeModel()

        XCTAssertEqual(model.visibleProviders, Set(GaugeProvider.allCases))
    }

    func testWelcomeCompletionPersists() {
        let model = makeModel()
        XCTAssertFalse(model.hasCompletedWelcome)

        model.completeWelcome()

        XCTAssertTrue(model.hasCompletedWelcome)
        XCTAssertTrue(makeModel().hasCompletedWelcome)
    }

    private func makeModel() -> AppModel {
        let snapshot = UsageSnapshot(
            fiveHourWindow: nil,
            weeklyWindow: nil,
            badge: nil,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let stores = Dictionary(uniqueKeysWithValues: GaugeProvider.allCases.map {
            ($0, UsageStore(provider: CountingProvider(snapshot: snapshot), refreshInterval: 60))
        })
        return AppModel(defaults: defaults, stores: stores)
    }
}
