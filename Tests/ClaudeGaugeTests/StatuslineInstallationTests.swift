import Foundation
import XCTest
@testable import ClaudeGaugeCore

final class StatuslineInstallationTests: XCTestCase {
    private var temporaryHome: URL!
    private var locations: CacheLocations!
    private var sourceExecutable: URL!

    override func setUpWithError() throws {
        temporaryHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        locations = CacheLocations(homeDirectory: temporaryHome)
        sourceExecutable = temporaryHome.appendingPathComponent("source-capture")

        try FileManager.default.createDirectory(
            at: temporaryHome,
            withIntermediateDirectories: true
        )
        try Data("capture-binary".utf8).write(to: sourceExecutable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: sourceExecutable.path
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryHome)
    }

    func testInstallPreservesSettingsAndInstallsExecutable() throws {
        try writeSettings(Data(#"{"model":"opus","env":{"TOKEN":"secret"}}"#.utf8))

        let change = try StatuslineInstallation.install(
            sourceExecutable: sourceExecutable,
            locations: locations
        )

        XCTAssertEqual(change, .installed)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: locations.captureExecutable.path))
        XCTAssertEqual(try Data(contentsOf: locations.captureExecutable), Data("capture-binary".utf8))
        XCTAssertEqual(permissions(at: locations.captureExecutable), 0o755)
        XCTAssertEqual(permissions(at: locations.installDirectory), 0o700)

        let object = try StatuslineSettings.decodeObject(Data(contentsOf: locations.claudeSettingsFile))
        XCTAssertEqual(object["model"] as? String, "opus")
        XCTAssertEqual((object["env"] as? [String: Any])?["TOKEN"] as? String, "secret")
        let statusLine = try XCTUnwrap(object["statusLine"] as? [String: Any])
        XCTAssertEqual(statusLine["command"] as? String, locations.captureExecutable.path)
    }

    func testReinstallRepairsExecutablePermissionsEvenWhenBytesMatch() throws {
        _ = try StatuslineInstallation.install(
            sourceExecutable: sourceExecutable,
            locations: locations
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: locations.captureExecutable.path
        )

        let change = try StatuslineInstallation.install(
            sourceExecutable: sourceExecutable,
            locations: locations
        )

        XCTAssertEqual(change, .alreadyInstalled)
        XCTAssertEqual(permissions(at: locations.captureExecutable), 0o755)
    }

    func testInstallHelperDoesNotTouchExistingSettings() throws {
        let input = Data(
            #"{"statusLine":{"type":"command","command":"~/.claude/custom.sh"}}"#.utf8
        )
        try writeSettings(input)

        try StatuslineInstallation.installHelper(
            sourceExecutable: sourceExecutable,
            locations: locations
        )

        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: locations.captureExecutable.path))
        XCTAssertEqual(try Data(contentsOf: locations.claudeSettingsFile), input)
    }

    func testUnreadableSettingsFailClosedBeforeInstallingHelper() throws {
        try FileManager.default.createDirectory(
            at: locations.claudeSettingsFile,
            withIntermediateDirectories: true
        )

        XCTAssertThrowsError(
            try StatuslineInstallation.install(
                sourceExecutable: sourceExecutable,
                locations: locations
            )
        ) { error in
            XCTAssertEqual(error as? ClaudeUsageError, .unreadableSettings)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: locations.captureExecutable.path))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: locations.claudeSettingsFile.path,
                isDirectory: &isDirectory
            )
        )
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testUninstallRemovesOwnedSettingEvenWhenHelperIsMissing() throws {
        let input = Data(
            "{\"model\":\"opus\",\"statusLine\":{\"type\":\"command\",\"command\":\"\(locations.captureExecutable.path)\"}}".utf8
        )
        try writeSettings(input)

        let change = try StatuslineInstallation.uninstall(locations: locations)

        XCTAssertEqual(change, .removed)
        let object = try StatuslineSettings.decodeObject(Data(contentsOf: locations.claudeSettingsFile))
        XCTAssertNil(object["statusLine"])
        XCTAssertEqual(object["model"] as? String, "opus")
    }

    func testUninstallPreservesHelperForUnknownProjectReferences() throws {
        _ = try StatuslineInstallation.install(
            sourceExecutable: sourceExecutable,
            locations: locations
        )
        try Data("cache".utf8).write(to: locations.cacheFile)

        let change = try StatuslineInstallation.uninstall(locations: locations)

        XCTAssertEqual(change, .removed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: locations.captureExecutable.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: locations.cacheFile.path))
        let object = try StatuslineSettings.decodeObject(Data(contentsOf: locations.claudeSettingsFile))
        XCTAssertNil(object["statusLine"])
    }

    func testIntegratedCustomStatuslineBlocksHelperRemoval() throws {
        try FileManager.default.createDirectory(
            at: locations.installDirectory,
            withIntermediateDirectories: true
        )
        try Data("helper".utf8).write(to: locations.captureExecutable)
        let command = "tee >(\(locations.captureExecutable.path) >/dev/null) | custom"
        let input = Data(
            "{\"statusLine\":{\"type\":\"command\",\"command\":\"\(command)\"}}".utf8
        )
        try writeSettings(input)

        XCTAssertThrowsError(
            try StatuslineInstallation.uninstall(locations: locations)
        ) { error in
            XCTAssertEqual(
                error as? ClaudeUsageError,
                .integratedStatusLine(command: command)
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: locations.captureExecutable.path))
        XCTAssertEqual(try Data(contentsOf: locations.claudeSettingsFile), input)
    }

    func testForeignStatuslinePreventsInstallWithoutCopyingHelper() throws {
        let command = "~/.claude/other-statusline.sh"
        let input = Data(
            "{\"statusLine\":{\"type\":\"command\",\"command\":\"\(command)\"}}".utf8
        )
        try writeSettings(input)

        XCTAssertThrowsError(
            try StatuslineInstallation.install(
                sourceExecutable: sourceExecutable,
                locations: locations
            )
        ) { error in
            XCTAssertEqual(
                error as? ClaudeUsageError,
                .foreignStatusLine(command: command)
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: locations.captureExecutable.path))
        XCTAssertEqual(try Data(contentsOf: locations.claudeSettingsFile), input)
    }

    func testForeignStatuslineBlocksHelperRemoval() throws {
        try FileManager.default.createDirectory(
            at: locations.installDirectory,
            withIntermediateDirectories: true
        )
        try Data("helper".utf8).write(to: locations.captureExecutable)
        let command = "$HOME/.claude/claude-gauge/capture"
        let input = Data(
            "{\"statusLine\":{\"type\":\"command\",\"command\":\"\(command)\"}}".utf8
        )
        try writeSettings(input)

        XCTAssertThrowsError(
            try StatuslineInstallation.uninstall(locations: locations)
        ) { error in
            XCTAssertEqual(
                error as? ClaudeUsageError,
                .foreignStatusLine(command: command)
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: locations.captureExecutable.path))
        XCTAssertEqual(try Data(contentsOf: locations.claudeSettingsFile), input)
    }

    func testSymlinkedSettingsMutateTargetWithoutDetachingLink() throws {
        let target = temporaryHome.appendingPathComponent("managed-settings.json")
        let input = Data(#"{"model":"opus"}"#.utf8)
        try input.write(to: target)
        try FileManager.default.createDirectory(
            at: locations.claudeSettingsFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: locations.claudeSettingsFile,
            withDestinationURL: target
        )

        let change = try StatuslineInstallation.install(
            sourceExecutable: sourceExecutable,
            locations: locations
        )

        XCTAssertEqual(change, .installed)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: locations.claudeSettingsFile.path
            ),
            target.path
        )
        var targetObject = try StatuslineSettings.decodeObject(Data(contentsOf: target))
        XCTAssertEqual(targetObject["model"] as? String, "opus")
        XCTAssertNotNil(targetObject["statusLine"])

        XCTAssertEqual(try StatuslineInstallation.uninstall(locations: locations), .removed)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: locations.claudeSettingsFile.path
            ),
            target.path
        )
        targetObject = try StatuslineSettings.decodeObject(Data(contentsOf: target))
        XCTAssertEqual(targetObject["model"] as? String, "opus")
        XCTAssertNil(targetObject["statusLine"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: locations.captureExecutable.path))
    }

    private func writeSettings(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: locations.claudeSettingsFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: locations.claudeSettingsFile)
    }

    private func permissions(at url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
