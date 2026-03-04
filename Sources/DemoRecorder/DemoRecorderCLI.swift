import ApplicationServices
import AXAutomation
import Foundation

@main
struct DemoRecorderCLI {
  /// Entrypoint for the `DemoRecorder` command-line tool.
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

  /// Prints command usage and supported options.
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

  /// Executes the record command from parsed CLI arguments.
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

/// Parses `record` command options into a fully resolved configuration.
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
    let value = optionValue(args: args, index: i, option: option)

    switch option {
    case "--source":
      sourceVideoPath = value
    case "--output":
      outputPath = value
    case "--poster":
      posterPath = value
    case "--width":
      outputWidth = parsePositiveIntOption(value: value, option: "--width")
    case "--bitrate":
      targetBitrate = parseIntOption(value: value, option: "--bitrate")
    case "--fps":
      fps = parsePositiveIntOption(value: value, option: "--fps")
    default:
      failRecordArg("Unknown option: \(option)")
    }
    i += 2
  }

  guard let sourceVideoPath else {
    failRecordArg("--source is required.")
  }
  guard targetBitrate > 0 else {
    failRecordArg("--bitrate must be greater than 0.")
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

/// Returns the value associated with a CLI option at `index` or exits with usage text.
private func optionValue(args: [String], index: Int, option: String) -> String {
  guard index + 1 < args.count else {
    failRecordArg("Missing value for option '\(option)'.")
  }
  return args[index + 1]
}

/// Parses an integer argument value for a named CLI option.
private func parseIntOption(value: String, option: String) -> Int {
  guard let parsedValue = Int(value) else {
    failRecordArg("\(option) value '\(value)' is not a valid integer.")
  }
  return parsedValue
}

/// Parses a strictly positive integer argument value for a named CLI option.
private func parsePositiveIntOption(value: String, option: String) -> Int {
  let parsedValue = parseIntOption(value: value, option: option)
  guard parsedValue > 0 else {
    failRecordArg("\(option) must be greater than 0.")
  }
  return parsedValue
}

/// Prints a parse error with usage text, then exits.
private func failRecordArg(_ message: String) -> Never {
  print("Error: \(message)")
  DemoRecorderCLI.printUsage()
  exit(1)
}

/// Resolves an input path against the current working directory.
private func resolvePath(_ path: String, cwd: String) -> String {
  URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: cwd, isDirectory: true))
    .standardized.path
}

/// Verifies source input exists and accessibility permissions are granted.
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

/// Locates the front VidPare content window and returns its CGWindowID.
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

/// Removes old `*_trimmed` artifacts to avoid save-panel overwrite prompts.
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

/// Runs the final scaling/encoding/poster extraction step for the recording.
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
