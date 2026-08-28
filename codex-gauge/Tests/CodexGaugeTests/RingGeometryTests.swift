import XCTest
@testable import CodexGauge

final class RingGeometryTests: XCTestCase {
    func testCompensatesForRoundCapsAtMenuBarSizes() {
        XCTAssertEqual(
            RingGeometry.trimProgress(for: 0.81, centerRadius: 4.68, lineWidth: 2),
            0.741_985,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            RingGeometry.trimProgress(for: 0.93, centerRadius: 7.65, lineWidth: 2),
            0.888_391,
            accuracy: 0.000_001
        )
    }

    func testCompensatesForRoundCapsAtPopoverSize() {
        XCTAssertEqual(
            RingGeometry.trimProgress(for: 0.81, centerRadius: 52, lineWidth: 10),
            0.779_393,
            accuracy: 0.000_001
        )
    }

    func testTinyArcsUseExactButtCappedProgress() {
        XCTAssertFalse(
            RingGeometry.usesRoundedCaps(for: 0.02, centerRadius: 4.68, lineWidth: 2)
        )
        XCTAssertEqual(
            RingGeometry.trimProgress(for: 0.02, centerRadius: 4.68, lineWidth: 2),
            0.02
        )
        XCTAssertTrue(
            RingGeometry.usesRoundedCaps(for: 0.81, centerRadius: 4.68, lineWidth: 2)
        )
    }

    func testClampsInvalidAndBoundaryProgress() {
        XCTAssertEqual(RingGeometry.trimProgress(for: -.infinity, centerRadius: 1, lineWidth: 1), 0)
        XCTAssertEqual(RingGeometry.trimProgress(for: -1, centerRadius: 1, lineWidth: 1), 0)
        XCTAssertEqual(RingGeometry.trimProgress(for: 0, centerRadius: 1, lineWidth: 1), 0)
        XCTAssertEqual(RingGeometry.trimProgress(for: 1, centerRadius: 1, lineWidth: 1), 1)
        XCTAssertEqual(RingGeometry.trimProgress(for: 2, centerRadius: 1, lineWidth: 1), 1)
    }
}
