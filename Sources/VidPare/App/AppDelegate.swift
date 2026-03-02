import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidBecomeActive(_ notification: Notification) {
    guard
      let window = NSApplication.shared.windows.first(where: {
        $0.isVisible && !$0.isMiniaturized
      })
    else { return }
    window.makeKeyAndOrderFront(nil)
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      if let window = sender.windows.first {
        window.makeKeyAndOrderFront(nil)
      }
    }
    return true
  }
}
