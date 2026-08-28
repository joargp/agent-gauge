import Foundation
import XCTest
@testable import ClaudeGaugeCore

final class UsageCacheDecoderTests: XCTestCase {
    func testDecodesCapturePayload() throws {
        let payload = UsageCachePayload(
            fiveHour: CacheWindow(usedPercentage: 23.5, resetsAt: 1_738_425_600),
            sevenDay: CacheWindow(usedPercentage: 41.2, resetsAt: 1_738_857_600),
            capturedAt: 1_738_425_000,
            claudeCodeVersion: "2.1.250"
        )
        let data = try CaptureRunner.encode(payload)

        let snapshot = try UsageCacheDecoder.decode(data)

        XCTAssertEqual(snapshot.fiveHourWindow?.usedPercent, 23.5)
        XCTAssertEqual(snapshot.fiveHourWindow?.resetsAt, Date(timeIntervalSince1970: 1_738_425_600))
        XCTAssertEqual(snapshot.sevenDayWindow?.usedPercent, 41.2)
        XCTAssertEqual(snapshot.capturedAt, Date(timeIntervalSince1970: 1_738_425_000))
        XCTAssertEqual(snapshot.claudeCodeVersion, "2.1.250")
    }

    func testMissingWindowsDecodeToNil() throws {
        let data = Data(
            #"{"seven_day":{"used_percentage":50,"resets_at":1738857600},"captured_at":1738425000}"#.utf8
        )

        let snapshot = try UsageCacheDecoder.decode(data)

        XCTAssertNil(snapshot.fiveHourWindow)
        XCTAssertEqual(snapshot.sevenDayWindow?.usedPercent, 50)
    }

    func testInvalidCacheThrowsInvalidCache() {
        XCTAssertThrowsError(try UsageCacheDecoder.decode(Data("garbage".utf8))) { error in
            XCTAssertEqual(error as? ClaudeUsageError, .invalidCache)
        }
    }

    func testMissingCapturedAtThrowsInvalidCache() {
        let data = Data(
            #"{"five_hour":{"used_percentage":10,"resets_at":1738425600}}"#.utf8
        )

        XCTAssertThrowsError(try UsageCacheDecoder.decode(data)) { error in
            XCTAssertEqual(error as? ClaudeUsageError, .invalidCache)
        }
    }

    func testExtremeTimestampsAreRejected() {
        let extremeCapture = Data(
            #"{"captured_at":1e20,"five_hour":{"used_percentage":10,"resets_at":2000000000}}"#.utf8
        )
        let extremeReset = Data(
            #"{"captured_at":2000000000,"five_hour":{"used_percentage":10,"resets_at":1e20}}"#.utf8
        )

        for data in [extremeCapture, extremeReset] {
            XCTAssertThrowsError(try UsageCacheDecoder.decode(data)) { error in
                XCTAssertEqual(error as? ClaudeUsageError, .invalidCache)
            }
        }
    }
}
