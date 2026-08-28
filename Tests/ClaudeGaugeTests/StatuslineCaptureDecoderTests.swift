import Foundation
import XCTest
@testable import ClaudeGaugeCore

final class StatuslineCaptureDecoderTests: XCTestCase {
    func testDecodesCanonicalStatuslinePayload() throws {
        let data = Data(
            #"{"cwd":"/tmp","model":{"id":"claude-sonnet-4-5","display_name":"Sonnet 4.5"},"version":"2.1.250","rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},"seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}"#.utf8
        )

        let capture = try StatuslineCaptureDecoder.decode(data)

        XCTAssertTrue(capture.hadRateLimits)
        XCTAssertEqual(capture.fiveHour?.usedPercent, 23.5)
        XCTAssertEqual(capture.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_738_425_600))
        XCTAssertEqual(capture.sevenDay?.usedPercent, 41.2)
        XCTAssertEqual(capture.sevenDay?.resetsAt, Date(timeIntervalSince1970: 1_738_857_600))
        XCTAssertEqual(capture.modelDisplayName, "Sonnet 4.5")
        XCTAssertEqual(capture.claudeCodeVersion, "2.1.250")
    }

    func testMissingRateLimitsYieldsEmptyCapture() throws {
        let data = Data(
            #"{"cwd":"/tmp","model":{"display_name":"Sonnet 4.5"},"version":"2.1.250"}"#.utf8
        )

        let capture = try StatuslineCaptureDecoder.decode(data)

        XCTAssertFalse(capture.hadRateLimits)
        XCTAssertNil(capture.fiveHour)
        XCTAssertNil(capture.sevenDay)
        XCTAssertEqual(capture.modelDisplayName, "Sonnet 4.5")
    }

    func testNullWindowsDecodeToNil() throws {
        let data = Data(
            #"{"rate_limits":{"five_hour":null,"seven_day":{"used_percentage":50,"resets_at":1738857600}}}"#.utf8
        )

        let capture = try StatuslineCaptureDecoder.decode(data)

        XCTAssertTrue(capture.hadRateLimits)
        XCTAssertNil(capture.fiveHour)
        XCTAssertEqual(capture.sevenDay?.usedPercent, 50)
    }

    func testInvalidUsedPercentageIsDropped() throws {
        let data = Data(
            #"{"rate_limits":{"five_hour":{"used_percentage":null,"resets_at":1738425600}}}"#.utf8
        )

        let capture = try StatuslineCaptureDecoder.decode(data)

        XCTAssertNil(capture.fiveHour)
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try StatuslineCaptureDecoder.decode(Data("not json".utf8)))
    }
}
