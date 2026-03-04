import AVFoundation
@testable import VidPare
import XCTest

final class TimelineViewTests: XCTestCase {
  private let width: CGFloat = 900

  // MARK: - xPosition

  func testXPosition_atZero() {
    let pos = TimelineView.xPosition(for: .zero, totalSeconds: 30, in: width)
    XCTAssertEqual(pos, 0)
  }

  func testXPosition_atEnd() {
    let time = CMTime(seconds: 30, preferredTimescale: 600)
    let pos = TimelineView.xPosition(for: time, totalSeconds: 30, in: width)
    XCTAssertEqual(pos, width)
  }

  func testXPosition_atMidpoint() {
    let time = CMTime(seconds: 15, preferredTimescale: 600)
    let pos = TimelineView.xPosition(for: time, totalSeconds: 30, in: width)
    XCTAssertEqual(pos, 450, accuracy: 0.01)
  }

  func testXPosition_clampsNegative() {
    let time = CMTime(seconds: -5, preferredTimescale: 600)
    let pos = TimelineView.xPosition(for: time, totalSeconds: 30, in: width)
    XCTAssertEqual(pos, 0)
  }

  func testXPosition_clampsBeyondDuration() {
    let time = CMTime(seconds: 60, preferredTimescale: 600)
    let pos = TimelineView.xPosition(for: time, totalSeconds: 30, in: width)
    XCTAssertEqual(pos, width)
  }

  func testXPosition_invalidTime() {
    let pos = TimelineView.xPosition(for: .invalid, totalSeconds: 30, in: width)
    XCTAssertEqual(pos, 0)
  }

  func testXPosition_zeroTotalDuration() {
    let zero = TimelineView.xPosition(for: .zero, totalSeconds: 0, in: width)
    XCTAssertEqual(zero, 0)

    let nonZero = TimelineView.xPosition(
      for: CMTime(seconds: 5, preferredTimescale: 600), totalSeconds: 0, in: width
    )
    XCTAssertEqual(nonZero, 0)

    let invalid = TimelineView.xPosition(for: .invalid, totalSeconds: 0, in: width)
    XCTAssertEqual(invalid, 0)
  }

  // MARK: - trimHandleOffset

  func testStartHandleOffset_atLeftEdge_staysInBounds() {
    let offset = TimelineView.trimHandleOffset(isStart: true, x: 0, width: width)
    XCTAssertEqual(offset, 0, "Start handle at x=0 must stay within timeline bounds")
    XCTAssertGreaterThanOrEqual(offset, 0, "Handle must not go off-screen left")
  }

  func testStartHandleOffset_awayFromEdge_bracketsLeft() {
    let offset = TimelineView.trimHandleOffset(isStart: true, x: 150, width: width)
    XCTAssertEqual(offset, 138, "Start handle should bracket left of position")
  }

  func testEndHandleOffset_atRightEdge_staysInBounds() {
    let offset = TimelineView.trimHandleOffset(isStart: false, x: width, width: width)
    XCTAssertEqual(offset, width - 12, "End handle at x=width must stay within timeline bounds")
    XCTAssertLessThanOrEqual(offset + 12, width, "Handle must not go off-screen right")
  }

  func testEndHandleOffset_awayFromEdge_bracketsRight() {
    let offset = TimelineView.trimHandleOffset(isStart: false, x: 700, width: width)
    XCTAssertEqual(offset, 700, "End handle should bracket right of position")
  }

  func testBothHandles_alwaysWithinBounds() {
    let positions: [CGFloat] = [0, 1, 6, 12, 100, 450, 888, 899, 900]
    for x in positions {
      let startOffset = TimelineView.trimHandleOffset(isStart: true, x: x, width: width)
      XCTAssertGreaterThanOrEqual(startOffset, 0, "Start handle off-screen at x=\(x)")
      XCTAssertLessThanOrEqual(startOffset + 12, width, "Start handle beyond right edge at x=\(x)")

      let endOffset = TimelineView.trimHandleOffset(isStart: false, x: x, width: width)
      XCTAssertGreaterThanOrEqual(endOffset, 0, "End handle off-screen at x=\(x)")
      XCTAssertLessThanOrEqual(endOffset + 12, width, "End handle beyond right edge at x=\(x)")
    }
  }
}
