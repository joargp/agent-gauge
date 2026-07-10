import Foundation
import XCTest
@testable import CodexGauge

final class JSONLineBufferTests: XCTestCase {
    func testReassemblesFragmentedLinesAndReturnsMultipleMessages() {
        var buffer = JSONLineBuffer()

        XCTAssertTrue(buffer.append(Data(#"{"id":0"#.utf8)).isEmpty)
        let firstBatch = buffer.append(Data("}\n{\"id\":1}\r\npartial".utf8))

        XCTAssertEqual(firstBatch.map { String(decoding: $0, as: UTF8.self) }, [
            #"{"id":0}"#,
            #"{"id":1}"#
        ])
        XCTAssertEqual(buffer.pendingByteCount, 7)

        let secondBatch = buffer.append(Data("-line\n".utf8))
        XCTAssertEqual(secondBatch.map { String(decoding: $0, as: UTF8.self) }, ["partial-line"])
        XCTAssertEqual(buffer.pendingByteCount, 0)
    }
}
