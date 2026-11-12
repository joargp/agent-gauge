import ClaudeProvider
import Foundation
import XCTest
@testable import AgentGauge

final class UpdateModeTests: XCTestCase {
    func testModesMapToSparkleSwitchesAndBack() {
        for mode in UpdateMode.allCases {
            XCTAssertEqual(
                UpdateMode(checksAutomatically: mode.checksAutomatically, downloadsAutomatically: mode.downloadsAutomatically),
                mode
            )
        }
        XCTAssertFalse(UpdateMode.off.checksAutomatically)
        XCTAssertTrue(UpdateMode.check.checksAutomatically)
        XCTAssertFalse(UpdateMode.check.downloadsAutomatically)
        XCTAssertTrue(UpdateMode.download.downloadsAutomatically)
    }

    func testDownloadingWithoutChecksMeansOff() {
        XCTAssertEqual(UpdateMode(checksAutomatically: false, downloadsAutomatically: true), .off)
    }
}

final class UpdateStateTests: XCTestCase {
    private let offer = UpdateOffer(version: "0.2.0", notes: [], infoURL: nil)

    func testOnlyWaitingUpdatesAskForAttention() {
        XCTAssertTrue(UpdateState.available(offer, reply: { _ in }).wantsAttention)
        XCTAssertTrue(UpdateState.ready(offer, install: {}).wantsAttention)
        XCTAssertFalse(UpdateState.idle.wantsAttention)
        XCTAssertFalse(UpdateState.checking(cancel: {}).wantsAttention)
        XCTAssertFalse(UpdateState.upToDate.wantsAttention)
    }

    func testManualCheckIsBlockedWhileAnUpdateIsUnderway() {
        XCTAssertTrue(UpdateState.idle.allowsManualCheck)
        XCTAssertTrue(UpdateState.upToDate.allowsManualCheck)
        XCTAssertTrue(UpdateState.error(title: "", message: "", retry: {}).allowsManualCheck)
        XCTAssertFalse(UpdateState.ready(offer, install: {}).allowsManualCheck)
        XCTAssertFalse(UpdateState.downloading(offer, received: 0, expected: nil, cancel: {}).allowsManualCheck)
    }

    func testDownloadFraction() {
        XCTAssertNil(UpdateState.downloading(offer, received: 5, expected: nil, cancel: {}).downloadFraction)
        XCTAssertEqual(UpdateState.downloading(offer, received: 25, expected: 100, cancel: {}).downloadFraction, 0.25)
        XCTAssertEqual(UpdateState.downloading(offer, received: 120, expected: 100, cancel: {}).downloadFraction, 1)
    }

    func testReleaseNotesAreReadFromListItems() {
        let html = """
        <h2>Agent Gauge 0.2.0</h2>
        <ul>
          <li>Updates itself.</li>
          <li>Fixes <code>codex</code> rings &amp; colors
              after sleep.</li>
          <li>   </li>
        </ul>
        """
        XCTAssertEqual(ReleaseNotes.bulletPoints(fromHTML: html), [
            "Updates itself.",
            "Fixes codex rings & colors after sleep.",
        ])
        XCTAssertEqual(ReleaseNotes.bulletPoints(fromHTML: nil), [])
    }
}

@MainActor
final class UpdateModelTests: XCTestCase {
    func testUpdatesNeedBothAFeedAndAKey() {
        XCTAssertTrue(UpdateModel.isConfigured(["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": "abc"]))
        XCTAssertFalse(UpdateModel.isConfigured(["SUFeedURL": "https://example.com/appcast.xml"]))
        XCTAssertFalse(UpdateModel.isConfigured(["SUPublicEDKey": "abc"]))
        XCTAssertFalse(UpdateModel.isConfigured(["SUFeedURL": "", "SUPublicEDKey": "abc"]))
    }

    func testBuildsWithoutUpdateKeysHaveNoUpdater() {
        // The test bundle has neither key, like debug and ad hoc builds.
        let model = UpdateModel(bundle: Bundle(for: Self.self))
        XCTAssertFalse(model.isEnabled)
        XCTAssertEqual(model.mode, .off)
        XCTAssertFalse(model.canStartCheck)
    }
}

final class CaptureHelperRefreshTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("CaptureHelperRefreshTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func bundledHelper(_ contents: String) throws -> URL {
        let url = home.appendingPathComponent("bundled-capture")
        try Data(contents.utf8).write(to: url)
        return url
    }

    func testInstalledHelperIsReplacedWithTheBundledOne() throws {
        let locations = CacheLocations(homeDirectory: home)
        try FileManager.default.createDirectory(at: locations.installDirectory, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: locations.captureExecutable)

        let refreshed = CaptureHelperRefresh.refresh(bundled: try bundledHelper("new"), locations: locations)

        XCTAssertTrue(refreshed)
        XCTAssertEqual(try String(contentsOf: locations.captureExecutable, encoding: .utf8), "new")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: locations.captureExecutable.path))
    }

    func testNothingIsInstalledWhenClaudeWasNeverConnected() throws {
        let locations = CacheLocations(homeDirectory: home)

        let refreshed = CaptureHelperRefresh.refresh(bundled: try bundledHelper("new"), locations: locations)

        XCTAssertFalse(refreshed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: locations.captureExecutable.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: locations.claudeSettingsFile.path))
    }
}
