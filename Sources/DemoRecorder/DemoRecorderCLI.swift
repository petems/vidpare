import ApplicationServices
import AXAutomation
import Foundation

@main
struct DemoRecorderCLI {
  static func main() async throws {
    let args = CommandLine.arguments

    guard args.count >= 2 else {
      printUsage()
      exit(1)
    }

    switch args[1] {
    case "record":
      try await runRecord(args: Array(args.dropFirst(2)))
    case "help", "--help", "-h":
      printUsage()
    default:
      print("Unknown command: \(args[1])")
      printUsage()
      exit(1)
    }
  }

  static func printUsage() {
    print(
      """
      Usage: DemoRecorder record [options]

      Options:
        --source <path>   Path to the source video file to use in the demo (required)
        --output <path>   Path for the output MP4 (default: site/public/demo.mp4)
        --poster <path>   Path for the poster frame JPEG (optional)
        --width <int>     Output video width in pixels (default: 1920)
        --bitrate <int>   Output video bitrate in bps (default: 5000000)
        --fps <int>       Recording frame rate (default: 30)
      """)
  }

  static func runRecord(args: [String]) async throws {
    let config = try parseRecordArgs(args)
    validatePreconditions(config: config)

    print("DemoRecorder: Starting demo recording...")
    print("  Source video: \(config.resolvedSource)")
    print("  Output: \(config.resolvedOutput)")
    print("  Target bitrate: \(config.targetBitrate) bps")
    if let poster = config.resolvedPoster {
      print("  Poster: \(poster)")
    }

    // Remove any existing trimmed file to avoid the save panel overwrite confirmation
    cleanupTrimmedFiles(sourceVideoPath: config.resolvedSource)

    let launcher = AppLauncher()
    let pid = try launcher.launch(environment: [
      "VIDPARE_OPEN_FILE": config.resolvedSource
    ])
    defer { launcher.terminate() }

    let windowID = try findWindowID(pid: pid)

    let rawOutputURL = URL(fileURLWithPath: config.resolvedOutput + ".raw.mp4")
    let recorder = WindowRecorder(outputURL: rawOutputURL)
    try await recorder.start(windowID: windowID, fps: config.fps)

    do {
      print("[3/5] Running demo scenario...")
      let scenario = DemoScenario(pid: pid)
      try scenario.run()
    } catch {
      print("Scenario failed: \(error). Stopping recording...")
      _ = try? await recorder.stop()
      throw error
    }

    print("[4/5] Stopping recording...")
    let rawURL = try await recorder.stop()

    print("[5/5] Post-processing...")
    try await postProcess(rawURL: rawURL, config: config)

    try? FileManager.default.removeItem(at: rawURL)

    let fileSize =
      (try? FileManager.default.attributesOfItem(atPath: config.resolvedOutput))?[.size]
      as? Int64 ?? 0
    let sizeMB = Double(fileSize) / 1_000_000.0
    print("\nDone! Output: \(config.resolvedOutput) (\(String(format: "%.1f", sizeMB)) MB)")
  }
}

// MARK: - Config & Parsing

struct RecordConfig {
  let resolvedSource: String
  let resolvedOutput: String
  let resolvedPoster: String?
  let outputWidth: Int
  let targetBitrate: Int
  let fps: Int
}

private func parseRecordArgs(_ args: [String]) throws -> RecordConfig {
  var sourceVideoPath: String?
  var outputPath = "site/public/demo.mp4"
  var posterPath: String?
  var outputWidth = 1920
  var targetBitrate = 5_000_000
  var fps = 30

  var i = 0
  while i < args.count {
    let option = args[i]

    guard i + 1 < args.count else {
      print("Error: Missing value for option '\(option)'.")
      DemoRecorderCLI.printUsage()
      exit(1)
    }
    let value = args[i + 1]

    switch option {
    case "--source":
      sourceVideoPath = value
    case "--output":
      outputPath = value
    case "--poster":
      posterPath = value
    case "--width":
      outputWidth = Int(value) ?? 1920
    case "--bitrate":
      guard let parsedBitrate = Int(value) else {
        print("Error: --bitrate value '\(value)' is not a valid integer.")
        DemoRecorderCLI.printUsage()
        exit(1)
      }
      targetBitrate = parsedBitrate
    case "--fps":
      fps = Int(value) ?? 30
    default:
      print("Unknown option: \(option)")
      DemoRecorderCLI.printUsage()
      exit(1)
    }
    i += 2
  }

  guard let sourceVideoPath else {
    print("Error: --source is required.")
    DemoRecorderCLI.printUsage()
    exit(1)
  }
  guard targetBitrate > 0 else {
    print("Error: --bitrate must be greater than 0.")
    DemoRecorderCLI.printUsage()
    exit(1)
  }

  let cwd = FileManager.default.currentDirectoryPath
  return RecordConfig(
    resolvedSource: resolvePath(sourceVideoPath, cwd: cwd),
    resolvedOutput: resolvePath(outputPath, cwd: cwd),
    resolvedPoster: posterPath.map { resolvePath($0, cwd: cwd) },
    outputWidth: outputWidth,
    targetBitrate: targetBitrate,
    fps: fps
  )
}

private func resolvePath(_ path: String, cwd: String) -> String {
  URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: cwd, isDirectory: true))
    .standardized.path
}

private func validatePreconditions(config: RecordConfig) {
  guard FileManager.default.fileExists(atPath: config.resolvedSource) else {
    print("Error: Source video not found at '\(config.resolvedSource)'.")
    exit(1)
  }
  guard AXIsProcessTrusted() else {
    print(
      "Error: Accessibility permissions not granted. "
        + "Add your terminal to System Settings > Privacy & Security > Accessibility.")
    exit(1)
  }
}

// MARK: - Window Discovery

private func findWindowID(pid: pid_t) throws -> CGWindowID {
  print("[1/5] Launching VidPare...")
  let app = axApp(for: pid)
  let windows = axWindows(of: app)
  guard let window = windows.first(where: { axTitle(of: $0)?.contains("VidPare") == true })
    ?? windows.last
  else {
    print("Error: No VidPare window found.")
    exit(1)
  }

  print("[2/5] Setting up screen recording...")
  let windowList =
    CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[CFString: Any]] ?? []
  let appWindows = windowList.filter {
    ($0[kCGWindowOwnerPID] as? pid_t) == pid
      && ($0[kCGWindowLayer] as? Int) == 0
  }

  let axWindowTitle = axTitle(of: window) ?? "VidPare"
  guard
    let windowInfo = appWindows.first(where: {
      ($0[kCGWindowName as CFString] as? String)?.contains(axWindowTitle) == true
    }) ?? appWindows.first,
    let windowID = windowInfo[kCGWindowNumber] as? CGWindowID
  else {
    print("Error: Could not find window ID for recording.")
    exit(1)
  }

  return windowID
}

// MARK: - Cleanup

private func cleanupTrimmedFiles(sourceVideoPath: String) {
  let sourceURL = URL(fileURLWithPath: sourceVideoPath)
  let baseName = sourceURL.deletingPathExtension().lastPathComponent
  let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

  let sourceDir = sourceURL.deletingLastPathComponent().path
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
      print("  Cleaned up: \(fullPath)")
    }
  }
}

// MARK: - Post-Processing

private func postProcess(rawURL: URL, config: RecordConfig) async throws {
  let finalOutputURL = URL(fileURLWithPath: config.resolvedOutput)
  let posterURL = config.resolvedPoster.map { URL(fileURLWithPath: $0) }

  let processor = PostProcessor(
    inputURL: rawURL,
    outputURL: finalOutputURL,
    posterURL: posterURL,
    targetWidth: config.outputWidth,
    targetBitrate: config.targetBitrate
  )
  try await processor.process()
}
