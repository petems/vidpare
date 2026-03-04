import XCTest

final class TrimHandleTests: XCTestCase {
  private let launcher = AppLauncher()
  private var pid: pid_t = 0

  private var fixturePath: String {
    let cwd = FileManager.default.currentDirectoryPath
    return "\(cwd)/Tests/VidPareTests/Fixtures/sample.mp4"
  }

  override func setUpWithError() throws {
    try super.setUpWithError()

    guard AXIsProcessTrusted() else {
      throw XCTSkip(
        "Accessibility permissions required. Add Terminal (or your IDE) to "
          + "System Settings > Privacy & Security > Accessibility."
      )
    }

    guard FileManager.default.fileExists(atPath: fixturePath) else {
      throw XCTSkip("Missing fixture: \(fixturePath)")
    }

    pid = try launcher.launch(openingFile: fixturePath)
  }

  override func tearDown() {
    launcher.terminate()
    super.tearDown()
  }

  // MARK: - Trim Handle Tests

  func testVideoLoads_timelineAndHandlesVisible() {
    let app = axApp(for: pid)

    var timeline: AXUIElement?
    let found = waitFor(timeout: 10.0) {
      guard let window = axWindows(of: app).first else { return false }
      timeline = findElement(withIdentifier: "vidpare.timeline", in: window)
      return timeline != nil
    }
    XCTAssertTrue(found, "Timeline should be visible after opening a video")

    guard let window = axWindows(of: app).first else {
      return XCTFail("No window")
    }
    let startHandle = findElement(withIdentifier: "vidpare.trimHandle.start", in: window)
    let endHandle = findElement(withIdentifier: "vidpare.trimHandle.end", in: window)
    XCTAssertNotNil(startHandle, "Start trim handle should be present")
    XCTAssertNotNil(endHandle, "End trim handle should be present")
  }

  func testTrimHandles_atEdge_areWithinTimelineBounds() {
    let app = axApp(for: pid)

    var timeline: AXUIElement?
    let loaded = waitFor(timeout: 10.0) {
      guard let window = axWindows(of: app).first else { return false }
      timeline = findElement(withIdentifier: "vidpare.timeline", in: window)
      return timeline != nil
    }
    guard loaded, let timeline else {
      return XCTFail("Timeline did not appear")
    }

    guard let window = axWindows(of: app).first else {
      return XCTFail("No window")
    }

    guard let timelineFrame = axFrame(of: timeline) else {
      return XCTFail("Could not get timeline frame")
    }

    guard
      let startHandle = findElement(
        withIdentifier: "vidpare.trimHandle.start",
        in: window
      ),
      let endHandle = findElement(
        withIdentifier: "vidpare.trimHandle.end",
        in: window
      )
    else {
      return XCTFail("Trim handles not found")
    }

    guard let startFrame = axFrame(of: startHandle) else {
      return XCTFail("Could not get start handle frame")
    }
    guard let endFrame = axFrame(of: endHandle) else {
      return XCTFail("Could not get end handle frame")
    }

    XCTAssertGreaterThanOrEqual(
      startFrame.maxX,
      timelineFrame.minX,
      "Start handle right edge must reach the timeline left boundary"
    )

    XCTAssertLessThanOrEqual(
      endFrame.minX,
      timelineFrame.maxX,
      "End handle left edge must be within the timeline right boundary"
    )
  }

  func testStartHandle_canBeDraggedFromEdge() {
    let app = axApp(for: pid)

    var startHandle: AXUIElement?
    let loaded = waitFor(timeout: 10.0) {
      guard let window = axWindows(of: app).first else { return false }
      startHandle = findElement(
        withIdentifier: "vidpare.trimHandle.start",
        in: window
      )
      return startHandle != nil
    }
    guard loaded, let startHandle else {
      return XCTFail("Start handle did not appear")
    }

    guard let initialFrame = axFrame(of: startHandle) else {
      return XCTFail("Could not get start handle frame")
    }
    let initialX = initialFrame.midX

    let dragStart = CGPoint(x: initialFrame.midX, y: initialFrame.midY)
    let dragEnd = CGPoint(x: initialFrame.midX + 100, y: initialFrame.midY)
    simulateDrag(from: dragStart, to: dragEnd)

    Thread.sleep(forTimeInterval: 0.3)

    guard let newFrame = axFrame(of: startHandle) else {
      return XCTFail("Could not get start handle frame after drag")
    }

    XCTAssertGreaterThan(
      newFrame.midX,
      initialX + 20,
      "Start handle should move right after drag (was \(initialX), now \(newFrame.midX))"
    )
  }

  func testEndHandle_canBeDraggedFromEdge() {
    let app = axApp(for: pid)

    var endHandle: AXUIElement?
    let loaded = waitFor(timeout: 10.0) {
      guard let window = axWindows(of: app).first else { return false }
      endHandle = findElement(
        withIdentifier: "vidpare.trimHandle.end",
        in: window
      )
      return endHandle != nil
    }
    guard loaded, let endHandle else {
      return XCTFail("End handle did not appear")
    }

    guard let initialFrame = axFrame(of: endHandle) else {
      return XCTFail("Could not get end handle frame")
    }
    let initialX = initialFrame.midX

    let dragStart = CGPoint(x: initialFrame.midX, y: initialFrame.midY)
    let dragEnd = CGPoint(x: initialFrame.midX - 100, y: initialFrame.midY)
    simulateDrag(from: dragStart, to: dragEnd)

    Thread.sleep(forTimeInterval: 0.3)

    guard let newFrame = axFrame(of: endHandle) else {
      return XCTFail("Could not get end handle frame after drag")
    }

    XCTAssertLessThan(
      newFrame.midX,
      initialX - 20,
      "End handle should move left after drag (was \(initialX), now \(newFrame.midX))"
    )
  }
}
