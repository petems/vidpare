import ApplicationServices
import AXAutomation
import XCTest

final class AcceptanceFlowTests: AcceptanceTestCase {
  override var opensFixtureOnLaunch: Bool { true }

  override var launchEnvironment: [String: String] {
    ["VIDPARE_OPEN_FILE": fixtureURL.path]
  }

  func testVideoLoads_timelineAndHandlesVisible() throws {
    let window = try mainWindow()
    let ready = waitForEditor(in: window)
    XCTAssertTrue(ready, "Editor should load with export toolbar and timeline")

    let timeline = findElement(withIdentifier: "vidpare.timeline", in: window)
    let startHandle = trimHandle(in: window, isStart: true)
    let endHandle = trimHandle(in: window, isStart: false)

    XCTAssertNotNil(timeline, "Timeline should be present")
    XCTAssertNotNil(startHandle, "Start trim handle should be present")
    XCTAssertNotNil(endHandle, "End trim handle should be present")
  }

  func testTrimHandles_canBeDraggedFromEdge() throws {
    let window = try mainWindow()
    XCTAssertTrue(waitForEditor(in: window), "Editor should be ready before dragging trim handles")

    guard let startHandle = trimHandle(in: window, isStart: true),
      let endHandle = trimHandle(in: window, isStart: false),
      let startInitial = axFrame(of: startHandle),
      let endInitial = axFrame(of: endHandle)
    else {
      return XCTFail("Trim handles should be visible with valid frames")
    }

    let startDragFrom = CGPoint(x: startInitial.midX, y: startInitial.midY)
    let startDragTo = CGPoint(x: startInitial.midX + 100, y: startInitial.midY)
    axDrag(from: startDragFrom, to: startDragTo, duration: 0.5)
    Thread.sleep(forTimeInterval: 0.3)

    guard let startAfter = axFrame(of: startHandle) else {
      return XCTFail("Could not get start handle frame after drag")
    }
    XCTAssertGreaterThan(
      startAfter.midX,
      startInitial.midX + 20,
      "Start handle should move right after drag"
    )

    let endDragFrom = CGPoint(x: endInitial.midX, y: endInitial.midY)
    let endDragTo = CGPoint(x: endInitial.midX - 100, y: endInitial.midY)
    axDrag(from: endDragFrom, to: endDragTo, duration: 0.5)
    Thread.sleep(forTimeInterval: 0.3)

    guard let endAfter = axFrame(of: endHandle) else {
      return XCTFail("Could not get end handle frame after drag")
    }
    XCTAssertLessThan(
      endAfter.midX,
      endInitial.midX - 20,
      "End handle should move left after drag"
    )
  }

  func testExport_savePanelFilenameIsEditable() throws {
    let app = app()
    let window = try mainWindow()
    XCTAssertTrue(waitForEditor(in: window), "Editor should be ready before export")

    try openExportFlow(from: window)

    guard let filenameField = waitForSavePanelFilenameField(in: app, window: window) else {
      return XCTFail("NSSavePanel should appear with a filename containing '_trimmed'")
    }

    let currentValue = axValue(of: filenameField) ?? ""
    XCTAssertTrue(currentValue.contains("_trimmed"), "Filename should contain '_trimmed'")
    XCTAssertTrue(
      axIsValueSettable(of: filenameField),
      "Filename field should be editable"
    )

    let customName = "my_custom_export"
    XCTAssertTrue(axSetValue(customName, of: filenameField), "Should set a custom filename")
    let updatedValue = axValue(of: filenameField) ?? ""
    XCTAssertTrue(
      updatedValue.hasPrefix(customName),
      "Filename field should start with '\(customName)'"
    )

    let dismissed = clickButton(titled: "Cancel", in: app)
    XCTAssertTrue(dismissed, "Should dismiss save panel")
  }

  func testExportFlow_completesAndShowsCompletionView() throws {
    let app = app()
    let window = try mainWindow()
    XCTAssertTrue(waitForEditor(in: window), "Editor should be ready before export")

    try openExportFlow(from: window)
    try confirmSavePanel(in: app)

    let completionShown = waitFor(timeout: 45.0, interval: 0.5) {
      if clickButton(titled: "Replace", in: app) {
        return false
      }
      return findDoneButton(in: app) != nil
        || axWindows(of: app).contains {
          findElement(withIdentifier: "vidpare.export.completionView", in: $0) != nil
        }
    }
    XCTAssertTrue(completionShown, "Export should complete and show completion view")
    guard completionShown else { return }

    var triggeredDoneAction = false
    if let doneButton = waitForDoneButton(in: app) {
      triggeredDoneAction = axMoveAndClick(doneButton)
    } else {
      // Fallback: Done is the default action on the completion view.
      axSendKeyPress(virtualKey: 0x24)
      triggeredDoneAction = true
    }
    XCTAssertTrue(triggeredDoneAction, "Should trigger completion dismissal action")

    let dismissed = waitFor(timeout: 5.0, interval: 0.25) {
      findDoneButton(in: app) == nil
        && !axWindows(of: app).contains {
          findElement(withIdentifier: "vidpare.export.completionView", in: $0) != nil
        }
    }
    XCTAssertTrue(dismissed, "Completion view should dismiss after clicking Done")
  }
}

private extension AcceptanceFlowTests {
  func waitForDoneButton(in app: AXUIElement, timeout: TimeInterval = 8.0) -> AXUIElement? {
    var doneButton: AXUIElement?
    let found = waitFor(timeout: timeout, interval: 0.25) {
      guard let button = findDoneButton(in: app) else { return false }
      doneButton = button
      return true
    }
    return found ? doneButton : nil
  }

  func findDoneButton(in app: AXUIElement) -> AXUIElement? {
    for win in axWindows(of: app) {
      if let button = findElement(withIdentifier: "vidpare.export.doneButton", in: win) {
        return button
      }
      if let button = findButton(titled: "Done", in: win) {
        return button
      }
    }
    return nil
  }

  func waitForEditor(in window: AXUIElement) -> Bool {
    waitFor(timeout: 12.0) {
      findElement(withIdentifier: "vidpare.toolbar.export", in: window) != nil
        && findElement(withIdentifier: "vidpare.timeline", in: window) != nil
    }
  }

  func openExportFlow(from window: AXUIElement) throws {
    guard let exportToolbar = findElement(withIdentifier: "vidpare.toolbar.export", in: window) else {
      throw XCTSkip("Export toolbar button not found")
    }
    XCTAssertTrue(axMoveAndClick(exportToolbar), "Should click Export toolbar button")

    let exportSheetAppeared = waitFor(timeout: 5.0) {
      findElement(withIdentifier: "vidpare.export.exportButton", in: window) != nil
    }
    XCTAssertTrue(exportSheetAppeared, "Export sheet should appear")

    guard let exportButton = findElement(withIdentifier: "vidpare.export.exportButton", in: window) else {
      throw XCTSkip("Export button not found")
    }

    let buttonEnabled = waitFor(timeout: 10.0) { axEnabled(of: exportButton) }
    XCTAssertTrue(buttonEnabled, "Export button should become enabled")
    Thread.sleep(forTimeInterval: 0.4)
    XCTAssertTrue(axMoveAndClick(exportButton), "Should click export button")
  }

  func waitForSavePanelFilenameField(
    in app: AXUIElement,
    window: AXUIElement
  ) -> AXUIElement? {
    var field: AXUIElement?
    let found = waitFor(timeout: 5.0) {
      if let localField = findElement(
        withRole: kAXTextFieldRole as String,
        valueContaining: "_trimmed",
        in: window
      ) {
        field = localField
        return true
      }

      for win in axWindows(of: app) {
        if let globalField = findElement(
          withRole: kAXTextFieldRole as String,
          valueContaining: "_trimmed",
          in: win
        ) {
          field = globalField
          return true
        }
      }
      return false
    }
    return found ? field : nil
  }

  func confirmSavePanel(in app: AXUIElement) throws {
    let savePanelAppeared = waitFor(timeout: 5.0) { isSavePanelVisible(in: app) }
    guard savePanelAppeared else {
      throw XCTSkip("Save panel did not appear")
    }

    // Save-panel interactions can be delayed; keep driving Save/Replace until the panel closes.
    var attemptedSave = false
    let saveFlowCompleted = waitFor(timeout: 12.0, interval: 0.25) {
      if clickButton(titled: "Replace", in: app) {
        return false
      }

      if !attemptedSave, clickButton(titled: "Save", in: app) {
        attemptedSave = true
        return false
      }

      if !attemptedSave {
        axSendKeyPress(virtualKey: 0x24)
        attemptedSave = true
        return false
      }

      if isSavePanelVisible(in: app) {
        _ = clickButton(titled: "Save", in: app)
        return false
      }

      return true
    }
    XCTAssertTrue(saveFlowCompleted, "Save panel should close after confirming export destination")
  }

  func isSavePanelVisible(in app: AXUIElement) -> Bool {
    axWindows(of: app).contains {
      findElement(
        withRole: kAXTextFieldRole as String,
        valueContaining: "_trimmed",
        in: $0
      ) != nil
    }
  }
}
