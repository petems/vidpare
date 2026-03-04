import AppKit
import Foundation

final class AppLauncher {
  private var process: Process?

  var binaryPath: String {
    ProcessInfo.processInfo.environment["VIDPARE_BINARY"]
      ?? ".build/debug/VidPare"
  }

  func launch() throws -> pid_t {
    let url = URL(fileURLWithPath: binaryPath)
    guard FileManager.default.isExecutableFile(atPath: url.path) else {
      throw AppLauncherError.binaryNotFound(binaryPath)
    }

    let proc = Process()
    proc.executableURL = url
    try proc.run()
    self.process = proc

    // Wait for the app to register with the window server
    Thread.sleep(forTimeInterval: 2.0)
    return proc.processIdentifier
  }

  func terminate() {
    guard let process, process.isRunning else { return }
    process.terminate()
    process.waitUntilExit()
    self.process = nil
  }
}

enum AppLauncherError: Error, CustomStringConvertible {
  case binaryNotFound(String)

  var description: String {
    switch self {
    case .binaryNotFound(let path):
      return "VidPare binary not found at '\(path)'. Run 'swift build' first."
    }
  }
}
