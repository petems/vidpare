import ApplicationServices
import Foundation

final class AppLauncher {
  private var process: Process?

  var binaryPath: String {
    ProcessInfo.processInfo.environment["VIDPARE_BINARY"]
      ?? ".build/debug/VidPare"
  }

  func launch(openingFile filePath: String? = nil) throws -> pid_t {
    let url = URL(fileURLWithPath: binaryPath)
    guard FileManager.default.isExecutableFile(atPath: url.path) else {
      throw AppLauncherError.binaryNotFound(binaryPath)
    }

    let proc = Process()
    proc.executableURL = url
    if let filePath {
      var env = ProcessInfo.processInfo.environment
      env["VIDPARE_OPEN_FILE"] = filePath
      proc.environment = env
    }
    try proc.run()
    self.process = proc

    let pid = proc.processIdentifier
    let app = axApp(for: pid)
    let ready = waitFor(timeout: 10.0) { !axWindows(of: app).isEmpty }
    if !ready {
      terminate()
      throw AppLauncherError.appDidNotLaunch
    }
    return pid
  }

  func terminate() {
    guard let process, process.isRunning else { return }
    process.terminate()

    let exited = waitFor(timeout: 5.0, interval: 0.25) {
      !process.isRunning
    }
    if !exited {
      process.interrupt()
    }
    self.process = nil
  }
}

enum AppLauncherError: Error, CustomStringConvertible {
  case binaryNotFound(String)
  case appDidNotLaunch

  var description: String {
    switch self {
    case .binaryNotFound(let path):
      return "VidPare binary not found at '\(path)'. Run 'swift build' first."
    case .appDidNotLaunch:
      return "VidPare launched but no window appeared within timeout."
    }
  }
}
