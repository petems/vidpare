import ApplicationServices
import AXAutomation
import CoreGraphics
import Foundation

struct DemoScenario {
  let pid: pid_t

  func run() throws {
    let app = axApp(for: pid)
    let windows = axWindows(of: app)
    // Pick the SwiftUI content window (titled "VidPare"), not the system-managed window
    guard let window = windows.first(where: { axTitle(of: $0)?.contains("VidPare") == true })
      ?? windows.last
    else {
      throw ScenarioError.noWindow
    }

    // Phase 1–2: Wait for video to load (passed via VIDPARE_OPEN_FILE env var)
    print("  Phase 1-2: Waiting for video to load")
    let videoLoaded = waitFor(timeout: 15.0) {
      findElement(withIdentifier: "vidpare.toolbar.export", in: window) != nil
    }
    guard videoLoaded else {
      axDumpTree(element: window, label: "window-video-not-loaded")
      throw ScenarioError.videoDidNotLoad
    }
    sleep(for: 1.5)

    // Phase 3: Playback preview
    print("  Phase 3: Playback")
    try playPreview(window: window)

    // Phase 4: Set trim points
    print("  Phase 4: Setting trim points")
    try setTrimPoints(window: window)

    // Phase 5: Export
    print("  Phase 5: Export")
    try performExport(app: app, window: window)

    print("  Demo scenario complete.")
  }

  // MARK: - Phase 3: Playback

  private func playPreview(window: AXUIElement) throws {
    guard let playButton = findElement(withIdentifier: "vidpare.playPause", in: window) else {
      throw ScenarioError.elementNotFound("vidpare.playPause")
    }
    guard let timeline = findElement(withIdentifier: "vidpare.timeline", in: window) else {
      throw ScenarioError.elementNotFound("vidpare.timeline")
    }

    // Seek to the ~4s mark (matching where trim handles will be placed)
    try seekTimeline(timeline, toFraction: 4.0 / 14.0)
    sleep(for: 0.5)

    // Play through part of the trim region (~4s to ~6s = 2s of playback)
    axMoveAndClick(playButton)
    sleep(for: 2.0)
    axMoveAndClick(playButton)
    sleep(for: 0.5)
  }

  /// Click on the timeline at a given fraction to seek the playhead there.
  private func seekTimeline(_ timeline: AXUIElement, toFraction fraction: CGFloat) throws {
    guard let timelinePos = axPosition(of: timeline),
      let timelineSize = axSize(of: timeline)
    else {
      throw ScenarioError.cannotGetElementFrame("timeline")
    }
    let target = CGPoint(
      x: timelinePos.x + fraction * timelineSize.width,
      y: timelinePos.y + timelineSize.height / 2.0
    )
    let current = CGEvent(source: nil)?.location ?? target
    axSmoothMoveCursor(from: current, to: target, duration: 0.3)
    axPostMouseClick(at: target)
  }

  // MARK: - Phase 4: Trim Points

  private func setTrimPoints(window: AXUIElement) throws {
    guard let timeline = findElement(withIdentifier: "vidpare.timeline", in: window) else {
      throw ScenarioError.elementNotFound("vidpare.timeline")
    }
    guard
      let startHandle = findTrimHandle(
        in: window,
        primaryIdentifier: "vidpare.timeline.startHandle",
        legacyIdentifier: "vidpare.trimHandle.start"
      )
    else {
      throw ScenarioError.elementNotFound("vidpare.timeline.startHandle")
    }
    guard
      let endHandle = findTrimHandle(
        in: window,
        primaryIdentifier: "vidpare.timeline.endHandle",
        legacyIdentifier: "vidpare.trimHandle.end"
      )
    else {
      throw ScenarioError.elementNotFound("vidpare.timeline.endHandle")
    }

    // Drag start handle to ~4s mark (4/14 ≈ 0.29)
    try dragTrimHandle(handle: startHandle, timeline: timeline, toFraction: 4.0 / 14.0)
    sleep(for: 0.8)

    // Drag end handle to ~7s mark (7/14 = 0.50)
    try dragTrimHandle(handle: endHandle, timeline: timeline, toFraction: 7.0 / 14.0)
    sleep(for: 1.0)
  }

  private func findTrimHandle(
    in window: AXUIElement,
    primaryIdentifier: String,
    legacyIdentifier: String
  ) -> AXUIElement? {
    findElement(withIdentifier: primaryIdentifier, in: window)
      ?? findElement(withIdentifier: legacyIdentifier, in: window)
  }

  private func dragTrimHandle(
    handle: AXUIElement,
    timeline: AXUIElement,
    toFraction: CGFloat,
    duration: TimeInterval = 0.6
  ) throws {
    guard let handlePos = axPosition(of: handle),
      let handleSize = axSize(of: handle)
    else {
      throw ScenarioError.cannotGetElementFrame("trim handle")
    }
    guard let timelinePos = axPosition(of: timeline),
      let timelineSize = axSize(of: timeline)
    else {
      throw ScenarioError.cannotGetElementFrame("timeline")
    }

    let startPoint = CGPoint(
      x: handlePos.x + handleSize.width / 2.0,
      y: handlePos.y + handleSize.height / 2.0
    )
    let endPoint = CGPoint(
      x: timelinePos.x + toFraction * timelineSize.width,
      y: timelinePos.y + timelineSize.height / 2.0
    )

    let current = CGEvent(source: nil)?.location ?? startPoint
    axSmoothMoveCursor(from: current, to: startPoint, duration: 0.3)
    axDrag(from: startPoint, to: endPoint, duration: duration)
  }

  // MARK: - Phase 5: Export

  private func performExport(app: AXUIElement, window: AXUIElement) throws {
    guard
      let exportToolbar = findElement(
        withIdentifier: "vidpare.toolbar.export", in: window)
    else {
      throw ScenarioError.elementNotFound("vidpare.toolbar.export")
    }
    axMoveAndClick(exportToolbar)

    let exportSheetAppeared = waitFor(timeout: 5.0) {
      findElement(withIdentifier: "vidpare.export.exportButton", in: window) != nil
    }
    guard exportSheetAppeared else {
      throw ScenarioError.sheetNotAppeared("export sheet")
    }
    sleep(for: 1.0)

    try clickExportButton(in: window)
    try acceptSavePanel(app: app, window: window)
    try waitForExportCompletion(app: app)
  }

  private func clickExportButton(in window: AXUIElement) throws {
    guard
      let exportButton = findElement(
        withIdentifier: "vidpare.export.exportButton", in: window)
    else {
      throw ScenarioError.elementNotFound("vidpare.export.exportButton")
    }

    let buttonEnabled = waitFor(timeout: 10.0) {
      axEnabled(of: exportButton)
    }
    guard buttonEnabled else {
      throw ScenarioError.elementNotFound("export button (still disabled after timeout)")
    }
    sleep(for: 0.5)
    axMoveAndClick(exportButton)
  }

  private func acceptSavePanel(app: AXUIElement, window: AXUIElement) throws {
    let savePanelAppeared = waitFor(timeout: 5.0) {
      if findElement(
        withRole: kAXTextFieldRole as String,
        valueContaining: "_trimmed",
        in: window
      ) != nil { return true }
      return axWindows(of: app).contains { win in
        findElement(
          withRole: kAXTextFieldRole as String,
          valueContaining: "_trimmed",
          in: win
        ) != nil
      }
    }
    guard savePanelAppeared else {
      throw ScenarioError.sheetNotAppeared("save panel")
    }
    sleep(for: 0.5)

    let saveButtonFound = clickSavePanelButton(app: app, titled: "Save")
    if !saveButtonFound {
      axSendKeyPress(virtualKey: 0x24)
    }
    sleep(for: 1.0)

    handleOverwriteConfirmation(app: app)
  }

  private func handleOverwriteConfirmation(app: AXUIElement) {
    let replaceAppeared = waitFor(timeout: 2.0, interval: 0.25) {
      axWindows(of: app).contains { findButton(titled: "Replace", in: $0) != nil }
    }
    guard replaceAppeared else { return }
    for win in axWindows(of: app) {
      if let replaceBtn = findButton(titled: "Replace", in: win) {
        sleep(for: 0.3)
        axMoveAndClick(replaceBtn)
        break
      }
    }
  }

  private func waitForExportCompletion(app: AXUIElement) throws {
    let exportCompleted = waitFor(timeout: 30.0, interval: 0.5) {
      axWindows(of: app).contains {
        findElement(withIdentifier: "vidpare.export.completionView", in: $0) != nil
      }
    }
    guard exportCompleted else {
      throw ScenarioError.exportDidNotComplete
    }
    sleep(for: 2.0)

    for win in axWindows(of: app) {
      if let doneBtn = findElement(withIdentifier: "vidpare.export.doneButton", in: win) {
        axMoveAndClick(doneBtn)
        break
      }
    }
    sleep(for: 0.5)
  }

  // MARK: - Save Panel

  /// Find and click a button by title in the save panel (which may be a sheet or standalone window).
  @discardableResult
  private func clickSavePanelButton(app: AXUIElement, titled title: String) -> Bool {
    for win in axWindows(of: app) {
      if let btn = findButton(titled: title, in: win) {
        axMoveAndClick(btn)
        return true
      }
    }
    return false
  }

  private func sleep(for seconds: TimeInterval) {
    Thread.sleep(forTimeInterval: seconds)
  }
}

enum ScenarioError: Error, CustomStringConvertible {
  case noWindow
  case elementNotFound(String)
  case sheetNotAppeared(String)
  case videoDidNotLoad
  case cannotGetElementFrame(String)
  case exportDidNotComplete

  var description: String {
    switch self {
    case .noWindow: return "No app window found."
    case .elementNotFound(let id): return "UI element not found: \(id)"
    case .sheetNotAppeared(let name): return "\(name) did not appear."
    case .videoDidNotLoad: return "Video did not load into the editor."
    case .cannotGetElementFrame(let name): return "Cannot get frame for element: \(name)"
    case .exportDidNotComplete: return "Export did not complete within timeout."
    }
  }
}
