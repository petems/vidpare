import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ aNotification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
}

@main
struct VidPareApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  private var initialFileURL: URL? {
    if let path = ProcessInfo.processInfo.environment["VIDPARE_OPEN_FILE"] {
      return URL(fileURLWithPath: path)
    }
    return nil
  }

  var body: some Scene {
    WindowGroup {
      ContentView(initialFileURL: initialFileURL)
    }
    .windowStyle(.titleBar)
    .defaultSize(width: 960, height: 640)
    .commands {
      CommandGroup(replacing: .newItem) {}
    }
  }
}
