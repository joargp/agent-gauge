import Foundation
import XCTest
@testable import CodexGauge

final class CodexRateLimitDecoderTests: XCTestCase {
    func testDecodesCanonicalAppServerResponse() throws {
        let data = Data(
            #"{"id":1,"result":{"rateLimits":{"limitId":"codex","planType":"pro","primary":{"usedPercent":32.5,"windowDurationMins":300,"resetsAt":1783687313},"secondary":{"usedPercent":74,"windowDurationMins":10080,"resetsAt":1784238455},"rateLimitReachedType":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":null}}"#.utf8
        )
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let usage = try CodexRateLimitDecoder.decode(data, fetchedAt: fetchedAt)

        XCTAssertEqual(usage.planType, "pro")
        XCTAssertEqual(usage.fiveHourWindow?.remainingPercent, 67.5)
        XCTAssertEqual(usage.weeklyWindow?.remainingPercent, 26)
        XCTAssertEqual(usage.fiveHourWindow?.windowDurationMins, 300)
        XCTAssertEqual(usage.weeklyWindow?.windowDurationMins, 10_080)
        XCTAssertEqual(usage.fetchedAt, fetchedAt)
    }

    func testPrefersCodexEntryFromMultiLimitResponse() throws {
        let data = Data(
            #"{"id":1,"result":{"rateLimits":{"planType":"pro","primary":{"usedPercent":99,"windowDurationMins":300,"resetsAt":1},"secondary":null},"rateLimitsByLimitId":{"codex":{"planType":"plus","primary":{"usedPercent":10,"windowDurationMins":300,"resetsAt":2},"secondary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":3}}}}}"#.utf8
        )

        let usage = try CodexRateLimitDecoder.decode(data)

        XCTAssertEqual(usage.planType, "plus")
        XCTAssertEqual(usage.fiveHourWindow?.remainingPercent, 90)
        XCTAssertEqual(usage.weeklyWindow?.remainingPercent, 80)
    }

    func testMapsAuthenticationFailureWithoutLeakingMessage() {
        let data = Data(
            #"{"id":1,"error":{"code":-32600,"message":"chatgpt authentication required to read rate limits"}}"#.utf8
        )

        XCTAssertThrowsError(try CodexRateLimitDecoder.decode(data)) { error in
            XCTAssertEqual(error as? CodexUsageError, .notLoggedIn)
        }
    }

    func testRejectsResponseWithoutUsageWindows() {
        let data = Data(
            #"{"id":1,"result":{"rateLimits":{"planType":"pro","primary":null,"secondary":null}}}"#.utf8
        )

        XCTAssertThrowsError(try CodexRateLimitDecoder.decode(data)) { error in
            XCTAssertEqual(error as? CodexUsageError, .usageUnavailable)
        }
    }
}
