import AVFoundation
@testable import VidPare
import XCTest

final class TimeFormatterTests: XCTestCase {

    func testPreciseStringRollover() {
        // 59.999 seconds — rounding to 2 decimals gives 60.00,
        // which must roll over to 1:00.00 not "0:60.00"
        let time = CMTime(value: 59999, timescale: 1000)
        let result = TimeFormatter.preciseString(from: time)
        XCTAssertFalse(result.contains("60.00"), "Should not display 60.00 seconds, got: \(result)")
        XCTAssertEqual(result, "1:00.00")
    }

    func testPreciseStringNormal() {
        let time = CMTime(seconds: 65.5, preferredTimescale: 600)
        let result = TimeFormatter.preciseString(from: time)
        XCTAssertEqual(result, "1:05.50")
    }

    func testPreciseStringHours() {
        let time = CMTime(seconds: 3661.25, preferredTimescale: 600)
        let result = TimeFormatter.preciseString(from: time)
        XCTAssertEqual(result, "1:01:01.25")
    }

    func testPreciseStringInvalid() {
        XCTAssertEqual(TimeFormatter.preciseString(from: .indefinite), "--:--.--")
        XCTAssertEqual(TimeFormatter.preciseString(from: .invalid), "--:--.--")
    }
}
