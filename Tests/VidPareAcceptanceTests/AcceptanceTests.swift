import XCTest

final class AcceptanceTests: XCTestCase {
  private let launcher = AppLauncher()
  private var pid: pid_t = 0

  override func setUpWithError() throws {
    try super.setUpWithError()

    guard AXIsProcessTrusted() else {
      throw XCTSkip(
        "Accessibility permissions required. Add Terminal (or your IDE) to "
          + "System Settings > Privacy & Security > Accessibility."
      )
    }

    pid = try launcher.launch()
  }

  override func tearDown() {
    launcher.terminate()
    super.tearDown()
  }

  // MARK: - Launch Tests

  func testAppLaunches_hasWindow() {
    let app = axApp(for: pid)
    let hasWindow = waitFor {
      !axWindows(of: app).isEmpty
    }
    XCTAssertTrue(hasWindow, "App should have at least one window after launch")
  }

  func testAppLaunches_windowTitleIsVidPare() {
    let app = axApp(for: pid)
    var title: String?
    let found = waitFor {
      if let window = axWindows(of: app).first {
        title = axTitle(of: window)
        return title != nil
      }
      return false
    }
    XCTAssertTrue(found, "Should find a window")
    XCTAssertEqual(title, "VidPare", "Window title should be 'VidPare'")
  }

  func testAppLaunches_showsDropTarget() {
    let app = axApp(for: pid)
    var found = false
    let success = waitFor {
      guard let window = axWindows(of: app).first else { return false }
      // Search by accessibility identifier (set in ContentView)
      if findElement(withIdentifier: "vidpare.openFile", in: window) != nil {
        found = true
        return true
      }
      // Fallback: search by title
      let buttons = findElements(withRole: kAXButtonRole as String, in: window)
      found = buttons.contains { btn in
        let title = axTitle(of: btn) ?? ""
        return title.contains("Open File") || title.contains("Open")
      }
      return found
    }
    XCTAssertTrue(success, "Drop target should show Open File button on launch")
  }
}
