import ApplicationServices
import AXAutomation
import Foundation
import XCTest

class AcceptanceTestCase: XCTestCase {
  let launcher = AppLauncher()
  var pid: pid_t = 0

  var launchEnvironment: [String: String] { [:] }
  var opensFixtureOnLaunch: Bool { false }

  var fixtureURL: URL {
    let cwd = FileManager.default.currentDirectoryPath
    return URL(fileURLWithPath: "\(cwd)/Tests/VidPareTests/Fixtures/sample.mp4")
  }

  override func setUpWithError() throws {
    try super.setUpWithError()

    guard AXIsProcessTrusted() else {
      throw XCTSkip(
        "Accessibility permissions required. Add Terminal (or your IDE) to "
          + "System Settings > Privacy & Security > Accessibility."
      )
    }

    if opensFixtureOnLaunch {
      try ensureFixtureExists()
      cleanupTrimmedFiles()
    }

    pid = try launcher.launch(environment: launchEnvironment)
  }

  override func tearDown() {
    if opensFixtureOnLaunch {
      cleanupTrimmedFiles()
    }
    launcher.terminate()
    super.tearDown()
  }
}

extension AcceptanceTestCase {
  func app() -> AXUIElement {
    axApp(for: pid)
  }

  func mainWindow(timeout: TimeInterval = 10.0) throws -> AXUIElement {
    let app = app()
    var window: AXUIElement?
    let found = waitFor(timeout: timeout) {
      let windows = axWindows(of: app)
      window = windows.first(where: { axTitle(of: $0)?.contains("VidPare") == true }) ?? windows.first
      return window != nil
    }
    guard found, let window else {
      throw AcceptanceError.windowNotFound
    }
    return window
  }

  func ensureFixtureExists() throws {
    guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
      throw XCTSkip("Missing fixture: \(fixtureURL.path)")
    }
  }

  func cleanupTrimmedFiles() {
    let baseName = fixtureURL.deletingPathExtension().lastPathComponent
    let videoExtensions = Set(["mp4", "mov", "m4v"])
    let sourceDir = fixtureURL.deletingLastPathComponent().path
    let desktopDir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Desktop").path
    let downloadsDir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Downloads").path

    let fm = FileManager.default
    for dir in Set([sourceDir, desktopDir, downloadsDir]) {
      guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
      for file in files {
        let fileURL = URL(fileURLWithPath: file)
        let name = fileURL.deletingPathExtension().lastPathComponent
        let ext = fileURL.pathExtension.lowercased()
        guard videoExtensions.contains(ext),
          name == "\(baseName)_trimmed" || name.hasPrefix("\(baseName)_trimmed ")
        else { continue }
        let fullPath = (dir as NSString).appendingPathComponent(file)
        try? fm.removeItem(atPath: fullPath)
      }
    }
  }

  @discardableResult
  func clickButton(titled title: String, in app: AXUIElement) -> Bool {
    for win in axWindows(of: app) {
      if let button = findButton(titled: title, in: win) {
        return axMoveAndClick(button)
      }
    }
    return false
  }

  func trimHandle(in window: AXUIElement, isStart: Bool) -> AXUIElement? {
    if isStart {
      return findElement(withIdentifier: "vidpare.timeline.startHandle", in: window)
        ?? findElement(withIdentifier: "vidpare.trimHandle.start", in: window)
    }
    return findElement(withIdentifier: "vidpare.timeline.endHandle", in: window)
      ?? findElement(withIdentifier: "vidpare.trimHandle.end", in: window)
  }
}

enum AcceptanceError: Error {
  case windowNotFound
}
