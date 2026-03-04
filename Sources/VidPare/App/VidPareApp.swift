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

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .windowStyle(.titleBar)
    .defaultSize(width: 960, height: 640)
    .commands {
      CommandGroup(replacing: .newItem) {}
    }
  }
}
