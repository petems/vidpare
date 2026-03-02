import AppKit
import XCTest

@testable import VidPare

@MainActor
final class AppDelegateTests: XCTestCase {
  func testApplicationShouldHandleReopenReturnsTrue() {
    let delegate = AppDelegate()
    let result = delegate.applicationShouldHandleReopen(
      NSApplication.shared, hasVisibleWindows: true
    )
    XCTAssertTrue(result)
  }

  func testApplicationShouldHandleReopenReturnsTrueWhenNoVisibleWindows() {
    let delegate = AppDelegate()
    let result = delegate.applicationShouldHandleReopen(
      NSApplication.shared, hasVisibleWindows: false
    )
    XCTAssertTrue(result)
  }

  func testApplicationDidBecomeActiveDoesNotCrashWithNoWindows() {
    let delegate = AppDelegate()
    delegate.applicationDidBecomeActive(
      Notification(name: NSApplication.didBecomeActiveNotification)
    )
  }
}
