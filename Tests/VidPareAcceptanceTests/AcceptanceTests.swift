import ApplicationServices
import AXAutomation
import XCTest

final class AcceptanceSmokeTests: AcceptanceTestCase {
  func testAppLaunches_hasWindow() {
    let app = app()
    let hasWindow = waitFor { !axWindows(of: app).isEmpty }
    XCTAssertTrue(hasWindow, "App should have at least one window after launch")
  }

  func testAppLaunches_windowTitleIsVidPare() {
    let app = app()
    var title: String?
    let found = waitFor {
      guard let window = axWindows(of: app).first else { return false }
      title = axTitle(of: window)
      return title != nil
    }
    XCTAssertTrue(found, "Should find a window")
    XCTAssertEqual(title, "VidPare", "Window title should be 'VidPare'")
  }

  func testAppLaunches_showsDropTarget() throws {
    let window = try mainWindow()
    let foundDropTarget = waitFor {
      findElement(withIdentifier: "vidpare.dropTarget", in: window) != nil
    }
    XCTAssertTrue(foundDropTarget, "Drop target should be visible on launch")

    let openButtonFound = waitFor {
      findElement(withIdentifier: "vidpare.openFile", in: window) != nil
    }
    XCTAssertTrue(openButtonFound, "Open File button should be visible on launch")
  }

  func testAppLaunches_hasToolbarOpenButton() throws {
    let window = try mainWindow()
    var toolbarButton: AXUIElement?
    let found = waitFor {
      if let button = findElement(withIdentifier: "vidpare.toolbar.open", in: window) {
        toolbarButton = button
        return true
      }
      let buttons = findElements(withRole: kAXButtonRole as String, in: window)
      toolbarButton = buttons.first { axDescription(of: $0) == "Open" }
      return toolbarButton != nil
    }
    XCTAssertTrue(found, "Should find toolbar Open button")
  }
}
