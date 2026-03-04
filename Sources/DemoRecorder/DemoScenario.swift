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
      dumpTree(element: window, label: "window-video-not-loaded")
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
    moveAndClick(playButton)
    sleep(for: 3.0)
    moveAndClick(playButton)
    sleep(for: 0.5)
  }

  // MARK: - Phase 4: Trim Points

  private func setTrimPoints(window: AXUIElement) throws {
    guard let timeline = findElement(withIdentifier: "vidpare.timeline", in: window) else {
      throw ScenarioError.elementNotFound("vidpare.timeline")
    }

    // Drag start handle from left edge to ~4s mark (4/14 ≈ 0.29)
    try dragTrimHandle(timeline, fromFraction: 0.0, toFraction: 4.0 / 14.0, isStart: true)
    sleep(for: 0.8)

    // Drag end handle from right edge to ~7s mark (7/14 = 0.50)
    try dragTrimHandle(timeline, fromFraction: 1.0, toFraction: 7.0 / 14.0, isStart: false)
    sleep(for: 1.0)
  }

  private func dragTrimHandle(
    _ timeline: AXUIElement,
    fromFraction: CGFloat,
    toFraction: CGFloat,
    isStart: Bool,
    duration: TimeInterval = 0.6
  ) throws {
    guard let position = axPosition(of: timeline),
      let size = axSize(of: timeline)
    else {
      throw ScenarioError.cannotGetElementFrame("timeline")
    }

    let handleWidth: CGFloat = 12
    let midY = position.y + (size.height / 2.0)

    // Handles are clamped to stay within the timeline:
    // Start handle offset = max(0, x - 12), end handle offset = min(x, width - 12)
    let fromX: CGFloat
    if isStart {
      let handleOffset = max(0, fromFraction * size.width - handleWidth)
      fromX = position.x + handleOffset + (handleWidth / 2.0)
    } else {
      let handleOffset = min(fromFraction * size.width, size.width - handleWidth)
      fromX = position.x + handleOffset + (handleWidth / 2.0)
    }

    let toX = position.x + (toFraction * size.width)
    let startPoint = CGPoint(x: fromX, y: midY)
    let endPoint = CGPoint(x: toX, y: midY)

    // Smoothly move cursor to the handle
    let current = CGEvent(source: nil)?.location ?? startPoint
    smoothMoveCursor(from: current, to: startPoint, duration: 0.3)

    // Mouse down on the handle
    let mouseDown = CGEvent(
      mouseEventSource: Self.eventSource,
      mouseType: .leftMouseDown,
      mouseCursorPosition: startPoint,
      mouseButton: .left
    )
    mouseDown?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.05)

    // Smoothly drag to target position
    smoothDrag(from: startPoint, to: endPoint, duration: duration)

    // Mouse up at target
    let mouseUp = CGEvent(
      mouseEventSource: Self.eventSource,
      mouseType: .leftMouseUp,
      mouseCursorPosition: endPoint,
      mouseButton: .left
    )
    mouseUp?.post(tap: .cghidEventTap)
  }

  // MARK: - Phase 5: Export

  private func performExport(app: AXUIElement, window: AXUIElement) throws {
    guard
      let exportToolbar = findElement(
        withIdentifier: "vidpare.toolbar.export", in: window)
    else {
      throw ScenarioError.elementNotFound("vidpare.toolbar.export")
    }
    moveAndClick(exportToolbar)

    let exportSheetAppeared = waitFor(timeout: 5.0) {
      findElement(withIdentifier: "vidpare.export.exportButton", in: window) != nil
    }
    guard exportSheetAppeared else {
      throw ScenarioError.sheetNotAppeared("export sheet")
    }
    sleep(for: 1.0)

    guard
      let exportButton = findElement(
        withIdentifier: "vidpare.export.exportButton", in: window)
    else {
      throw ScenarioError.elementNotFound("vidpare.export.exportButton")
    }

    // Wait for capability loading (Export button becomes enabled once capabilities resolve)
    let buttonEnabled = waitFor(timeout: 10.0) {
      axEnabled(of: exportButton)
    }
    guard buttonEnabled else {
      throw ScenarioError.elementNotFound("export button (still disabled after timeout)")
    }
    sleep(for: 0.5)
    moveAndClick(exportButton)

    // Wait for save panel to appear (may be a sheet on the main window or a standalone window)
    let savePanelAppeared = waitFor(timeout: 5.0) {
      // Check the main window first (sheet case)
      if findElement(
        withRole: kAXTextFieldRole as String,
        valueContaining: "_trimmed",
        in: window
      ) != nil { return true }
      // Fall back to checking all windows (standalone case)
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

    // Accept default filename
    sendKeyPress(virtualKey: 0x24)  // Return
    sleep(for: 1.0)

    // Handle possible overwrite confirmation dialog ("Replace" button)
    for win in axWindows(of: app) {
      if let replaceBtn = findButton(titled: "Replace", in: win) {
        moveAndClick(replaceBtn)
        break
      }
    }

    // Wait for export to complete (export completion view appears)
    let exportCompleted = waitFor(timeout: 30.0, interval: 0.5) {
      findElement(withIdentifier: "vidpare.export.completionView", in: window) != nil
    }

    if exportCompleted {
      sleep(for: 2.0)
      // Click Done to dismiss the completion view
      if let doneBtn = findElement(withIdentifier: "vidpare.export.doneButton", in: window) {
        moveAndClick(doneBtn)
      }
      sleep(for: 0.5)
    } else {
      sleep(for: 3.0)
    }
  }

  // MARK: - Helpers

  /// Event source that suppresses real user mouse input during programmatic moves.
  private static let eventSource: CGEventSource? = {
    let source = CGEventSource(stateID: .hidSystemState)
    source?.localEventsSuppressionInterval = 0.5
    return source
  }()

  private func smoothMoveCursor(from start: CGPoint, to end: CGPoint, duration: TimeInterval) {
    let steps = max(Int(duration * 60), 10)
    let stepDelay = duration / Double(steps)

    for i in 1...steps {
      let t = Double(i) / Double(steps)
      let ease = t * t * (3.0 - 2.0 * t)
      let x = start.x + CGFloat(ease) * (end.x - start.x)
      let y = start.y + CGFloat(ease) * (end.y - start.y)

      let move = CGEvent(
        mouseEventSource: Self.eventSource,
        mouseType: .mouseMoved,
        mouseCursorPosition: CGPoint(x: x, y: y),
        mouseButton: .left
      )
      move?.post(tap: .cghidEventTap)
      Thread.sleep(forTimeInterval: stepDelay)
    }
  }

  private func smoothDrag(from start: CGPoint, to end: CGPoint, duration: TimeInterval) {
    let steps = max(Int(duration * 60), 10)
    let stepDelay = duration / Double(steps)

    for i in 1...steps {
      let t = Double(i) / Double(steps)
      let ease = t * t * (3.0 - 2.0 * t)
      let x = start.x + CGFloat(ease) * (end.x - start.x)
      let y = start.y + CGFloat(ease) * (end.y - start.y)

      let drag = CGEvent(
        mouseEventSource: Self.eventSource,
        mouseType: .leftMouseDragged,
        mouseCursorPosition: CGPoint(x: x, y: y),
        mouseButton: .left
      )
      drag?.post(tap: .cghidEventTap)
      Thread.sleep(forTimeInterval: stepDelay)
    }
  }

  /// Smoothly move the cursor to an AX element's center and click it.
  private func moveAndClick(_ element: AXUIElement, duration: TimeInterval = 0.3) {
    guard let position = axPosition(of: element),
      let size = axSize(of: element)
    else {
      // Fall back to AX press if we can't get the frame
      pressButton(element)
      return
    }
    let center = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
    let start = CGEvent(source: nil)?.location ?? center
    smoothMoveCursor(from: start, to: center, duration: duration)
    postMouseClick(at: center)
  }

  private func postMouseClick(at point: CGPoint) {
    let mouseDown = CGEvent(
      mouseEventSource: Self.eventSource,
      mouseType: .leftMouseDown,
      mouseCursorPosition: point,
      mouseButton: .left
    )
    mouseDown?.post(tap: .cghidEventTap)

    let mouseUp = CGEvent(
      mouseEventSource: Self.eventSource,
      mouseType: .leftMouseUp,
      mouseCursorPosition: point,
      mouseButton: .left
    )
    mouseUp?.post(tap: .cghidEventTap)
  }

  private func sendKeyPress(virtualKey: CGKeyCode, flags: CGEventFlags = []) {
    let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true)
    if !flags.isEmpty { keyDown?.flags = flags }
    keyDown?.post(tap: .cghidEventTap)
    let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false)
    if !flags.isEmpty { keyUp?.flags = flags }
    keyUp?.post(tap: .cghidEventTap)
  }

  private func sleep(for seconds: TimeInterval) {
    Thread.sleep(forTimeInterval: seconds)
  }

  private func dumpTree(element: AXUIElement, label: String, depth: Int = 0) {
    let indent = String(repeating: "  ", count: depth)
    let role = axRole(of: element) ?? "?"
    let id = axIdentifier(of: element) ?? ""
    let title = axTitle(of: element) ?? ""
    let desc = axDescription(of: element) ?? ""
    var parts = ["\(indent)[\(role)]"]
    if !id.isEmpty { parts.append("id=\"\(id)\"") }
    if !title.isEmpty { parts.append("title=\"\(title)\"") }
    if !desc.isEmpty { parts.append("desc=\"\(desc)\"") }
    if depth == 0 { FileHandle.standardError.write("  AX tree dump (\(label)):\n".data(using: .utf8)!) }
    FileHandle.standardError.write((parts.joined(separator: " ") + "\n").data(using: .utf8)!)
    if depth < 12 {
      for child in axChildren(of: element) {
        dumpTree(element: child, label: label, depth: depth + 1)
      }
    }
  }
}

enum ScenarioError: Error, CustomStringConvertible {
  case noWindow
  case elementNotFound(String)
  case sheetNotAppeared(String)
  case videoDidNotLoad
  case cannotGetElementFrame(String)

  var description: String {
    switch self {
    case .noWindow: return "No app window found."
    case .elementNotFound(let id): return "UI element not found: \(id)"
    case .sheetNotAppeared(let name): return "\(name) did not appear."
    case .videoDidNotLoad: return "Video did not load into the editor."
    case .cannotGetElementFrame(let name): return "Cannot get frame for element: \(name)"
    }
  }
}
