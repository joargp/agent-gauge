import Foundation
import XCTest
@testable import ClaudeProvider
import GaugeCore

final class StatuslineSettingsTests: XCTestCase {
    private let capturePath = "/Users/test/.claude/claude-gauge/capture"

    func testInstallsIntoEmptySettings() throws {
        let result = try StatuslineSettings.apply(settingsJSON: nil, capturePath: capturePath)
        let object = try StatuslineSettings.decodeObject(result.data)
        let statusLine = try XCTUnwrap(object["statusLine"] as? [String: Any])

        XCTAssertEqual(statusLine["type"] as? String, "command")
        XCTAssertEqual(statusLine["command"] as? String, capturePath)
        XCTAssertEqual(result.change, .installed)
    }

    func testPreservesExistingSettings() throws {
        let input = Data(#"{"model":"opus","env":{"FOO":"bar"}}"#.utf8)

        let result = try StatuslineSettings.apply(settingsJSON: input, capturePath: capturePath)
        let object = try StatuslineSettings.decodeObject(result.data)

        XCTAssertEqual(object["model"] as? String, "opus")
        XCTAssertEqual((object["env"] as? [String: Any])?["FOO"] as? String, "bar")
        XCTAssertNotNil(object["statusLine"])
    }

    func testAlreadyInstalledIsIdempotent() throws {
        let input = Data(
            #"{"statusLine":{"type":"command","command":"/Users/test/.claude/claude-gauge/capture"}}"#.utf8
        )

        let result = try StatuslineSettings.apply(settingsJSON: input, capturePath: capturePath)

        XCTAssertEqual(result.change, .alreadyInstalled)
    }

    func testDoesNotClaimAnotherClaudeGaugePath() {
        let input = Data(
            #"{"statusLine":{"type":"command","command":"/old/.claude/claude-gauge/capture"}}"#.utf8
        )

        XCTAssertThrowsError(
            try StatuslineSettings.apply(settingsJSON: input, capturePath: capturePath)
        ) { error in
            XCTAssertEqual(
                error as? ClaudeUsageError,
                .foreignStatusLine(command: "/old/.claude/claude-gauge/capture")
            )
        }
    }

    func testRefusesToReplaceForeignStatusline() {
        let input = Data(
            #"{"statusLine":{"type":"command","command":"~/.claude/my-statusline.sh"}}"#.utf8
        )

        XCTAssertThrowsError(
            try StatuslineSettings.apply(settingsJSON: input, capturePath: capturePath)
        ) { error in
            XCTAssertEqual(
                error as? ClaudeUsageError,
                .foreignStatusLine(command: "~/.claude/my-statusline.sh")
            )
        }
    }

    func testIntegratedCustomStatuslineIsAcceptedWithoutRewriting() throws {
        let command = "tee >(~/.claude/claude-gauge/capture >/dev/null) | ~/.claude/custom.sh"
        let input = Data(
            #"{"statusLine":{"type":"command","command":"tee >(~/.claude/claude-gauge/capture >/dev/null) | ~/.claude/custom.sh"}}"#.utf8
        )

        let result = try StatuslineSettings.apply(settingsJSON: input, capturePath: capturePath)
        let object = try StatuslineSettings.decodeObject(result.data)
        let statusLine = try XCTUnwrap(object["statusLine"] as? [String: Any])

        XCTAssertEqual(result.change, .alreadyInstalled)
        XCTAssertEqual(statusLine["command"] as? String, command)
        XCTAssertEqual(
            StatuslineSettings.inspect(settingsJSON: input, capturePath: capturePath),
            .integrated(command: command)
        )
    }

    func testRemovesOwnedStatusline() throws {
        let input = Data(
            #"{"model":"opus","statusLine":{"type":"command","command":"/Users/test/.claude/claude-gauge/capture"}}"#.utf8
        )

        let result = try StatuslineSettings.remove(
            settingsJSON: input,
            capturePath: capturePath
        )
        let object = try StatuslineSettings.decodeObject(result.data)

        XCTAssertEqual(result.change, .removed)
        XCTAssertNil(object["statusLine"])
        XCTAssertEqual(object["model"] as? String, "opus")
    }

    func testForeignStatuslineBlocksRemoval() {
        let input = Data(
            #"{"statusLine":{"type":"command","command":"~/.claude/my-statusline.sh"}}"#.utf8
        )

        XCTAssertThrowsError(
            try StatuslineSettings.remove(
                settingsJSON: input,
                capturePath: capturePath
            )
        ) { error in
            XCTAssertEqual(
                error as? ClaudeUsageError,
                .foreignStatusLine(command: "~/.claude/my-statusline.sh")
            )
        }
    }

    func testInspectDistinguishesStates() {
        XCTAssertEqual(
            StatuslineSettings.inspect(settingsJSON: nil, capturePath: capturePath),
            .missing
        )
        XCTAssertEqual(
            StatuslineSettings.inspect(
                settingsJSON: Data(#"{"statusLine":{"type":"command","command":"/Users/test/.claude/claude-gauge/capture"}}"#.utf8),
                capturePath: capturePath
            ),
            .installed(command: capturePath)
        )
        XCTAssertEqual(
            StatuslineSettings.inspect(
                settingsJSON: Data(#"{"statusLine":{"type":"command","command":"custom"}}"#.utf8),
                capturePath: capturePath
            ),
            .foreign(command: "custom")
        )
        XCTAssertEqual(
            StatuslineSettings.inspect(settingsJSON: Data("bad".utf8), capturePath: capturePath),
            .unreadable
        )
    }

    func testMalformedStatuslineIsNeverOverwrittenOrRemoved() {
        let input = Data(#"{"statusLine":"unexpected"}"#.utf8)

        XCTAssertEqual(
            StatuslineSettings.inspect(settingsJSON: input, capturePath: capturePath),
            .malformed
        )
        XCTAssertThrowsError(
            try StatuslineSettings.apply(settingsJSON: input, capturePath: capturePath)
        ) { error in
            XCTAssertEqual(error as? ClaudeUsageError, .malformedStatusLine)
        }
        XCTAssertThrowsError(
            try StatuslineSettings.remove(settingsJSON: input, capturePath: capturePath)
        ) { error in
            XCTAssertEqual(error as? ClaudeUsageError, .malformedStatusLine)
        }
    }

    func testIntegratedStatuslineMustBeDetachedBeforeRemoval() {
        let command = "tee >(~/.claude/claude-gauge/capture >/dev/null) | custom"
        let input = Data(
            #"{"statusLine":{"type":"command","command":"tee >(~/.claude/claude-gauge/capture >/dev/null) | custom"}}"#.utf8
        )

        XCTAssertThrowsError(
            try StatuslineSettings.remove(settingsJSON: input, capturePath: capturePath)
        ) { error in
            XCTAssertEqual(
                error as? ClaudeUsageError,
                .integratedStatusLine(command: command)
            )
        }
    }

    func testInvalidSettingsCannotBeOverwritten() {
        XCTAssertThrowsError(
            try StatuslineSettings.apply(settingsJSON: Data("bad".utf8), capturePath: capturePath)
        ) { error in
            XCTAssertEqual(error as? ClaudeUsageError, .invalidSettings)
        }
    }

    func testEmptyExistingSettingsCannotBeOverwritten() {
        XCTAssertThrowsError(
            try StatuslineSettings.apply(settingsJSON: Data(), capturePath: capturePath)
        ) { error in
            XCTAssertEqual(error as? ClaudeUsageError, .invalidSettings)
        }
    }
}
