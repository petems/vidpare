import ApplicationServices
import CoreGraphics
import Foundation

private let sharedEventSource: CGEventSource? = {
  let source = CGEventSource(stateID: .hidSystemState)
  source?.localEventsSuppressionInterval = 0.5
  return source
}()

/// Simulate a key press with optional modifiers.
public func axSendKeyPress(virtualKey: CGKeyCode, flags: CGEventFlags = []) {
  let keyDown = CGEvent(
    keyboardEventSource: sharedEventSource,
    virtualKey: virtualKey,
    keyDown: true
  )
  if !flags.isEmpty { keyDown?.flags = flags }
  keyDown?.post(tap: .cghidEventTap)

  let keyUp = CGEvent(
    keyboardEventSource: sharedEventSource,
    virtualKey: virtualKey,
    keyDown: false
  )
  if !flags.isEmpty { keyUp?.flags = flags }
  keyUp?.post(tap: .cghidEventTap)
}

/// Move the cursor smoothly from one point to another.
public func axSmoothMoveCursor(
  from start: CGPoint,
  to end: CGPoint,
  duration: TimeInterval
) {
  let safeDuration = max(0, duration)
  let steps = max(Int(safeDuration * 60), 10)
  let stepDelay = safeDuration / Double(steps)

  for step in 1...steps {
    let progress = Double(step) / Double(steps)
    let ease = progress * progress * (3.0 - 2.0 * progress)
    let point = CGPoint(
      x: start.x + CGFloat(ease) * (end.x - start.x),
      y: start.y + CGFloat(ease) * (end.y - start.y)
    )

    let move = CGEvent(
      mouseEventSource: sharedEventSource,
      mouseType: .mouseMoved,
      mouseCursorPosition: point,
      mouseButton: .left
    )
    move?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: stepDelay)
  }
}

/// Post a left mouse click at an absolute screen point.
@discardableResult
public func axPostMouseClick(at point: CGPoint) -> Bool {
  guard
    let mouseDown = CGEvent(
      mouseEventSource: sharedEventSource,
      mouseType: .leftMouseDown,
      mouseCursorPosition: point,
      mouseButton: .left
    ),
    let mouseUp = CGEvent(
      mouseEventSource: sharedEventSource,
      mouseType: .leftMouseUp,
      mouseCursorPosition: point,
      mouseButton: .left
    )
  else { return false }

  mouseDown.post(tap: .cghidEventTap)
  mouseUp.post(tap: .cghidEventTap)
  return true
}

/// Smoothly move the cursor to an element center and click it.
@discardableResult
public func axMoveAndClick(_ element: AXUIElement, duration: TimeInterval = 0.25) -> Bool {
  guard let position = axPosition(of: element), let size = axSize(of: element) else {
    return pressButton(element)
  }

  let center = CGPoint(x: position.x + size.width / 2.0, y: position.y + size.height / 2.0)
  let start = CGEvent(source: nil)?.location ?? center
  axSmoothMoveCursor(from: start, to: center, duration: duration)
  return axPostMouseClick(at: center)
}

/// Simulate a smooth mouse drag from one point to another.
@discardableResult
public func axDrag(
  from start: CGPoint,
  to end: CGPoint,
  duration: TimeInterval = 0.35
) -> Bool {
  func postMouseUp(at point: CGPoint) -> Bool {
    let mouseUp =
      CGEvent(
        mouseEventSource: sharedEventSource,
        mouseType: .leftMouseUp,
        mouseCursorPosition: point,
        mouseButton: .left
      )
      ?? CGEvent(
        mouseEventSource: nil,
        mouseType: .leftMouseUp,
        mouseCursorPosition: point,
        mouseButton: .left
      )
    guard let mouseUp else { return false }
    mouseUp.post(tap: .cghidEventTap)
    return true
  }

  guard let mouseDown = CGEvent(
    mouseEventSource: sharedEventSource,
    mouseType: .leftMouseDown,
    mouseCursorPosition: start,
    mouseButton: .left
  ) else { return false }

  mouseDown.post(tap: .cghidEventTap)
  Thread.sleep(forTimeInterval: 0.05)

  let safeDuration = max(0, duration)
  let steps = max(Int(safeDuration * 60), 10)
  let stepDelay = safeDuration / Double(steps)
  for step in 1...steps {
    let progress = Double(step) / Double(steps)
    let ease = progress * progress * (3.0 - 2.0 * progress)
    let point = CGPoint(
      x: start.x + CGFloat(ease) * (end.x - start.x),
      y: start.y + CGFloat(ease) * (end.y - start.y)
    )

    guard let drag = CGEvent(
      mouseEventSource: sharedEventSource,
      mouseType: .leftMouseDragged,
      mouseCursorPosition: point,
      mouseButton: .left
    ) else {
      _ = postMouseUp(at: point)
      return false
    }
    drag.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: stepDelay)
  }

  return postMouseUp(at: end)
}

/// Dump the AX tree rooted at an element for debugging flaky selector issues.
public func axDumpTree(element: AXUIElement, label: String, maxDepth: Int = 12, depth: Int = 0) {
  let indent = String(repeating: "  ", count: depth)
  let role = axRole(of: element) ?? "?"
  let id = axIdentifier(of: element) ?? ""
  let title = axTitle(of: element) ?? ""
  let description = axDescription(of: element) ?? ""

  var parts = ["\(indent)[\(role)]"]
  if !id.isEmpty { parts.append("id=\"\(id)\"") }
  if !title.isEmpty { parts.append("title=\"\(title)\"") }
  if !description.isEmpty { parts.append("desc=\"\(description)\"") }

  if depth == 0 {
    FileHandle.standardError.write(Data("  AX tree dump (\(label)):\n".utf8))
  }
  FileHandle.standardError.write(Data((parts.joined(separator: " ") + "\n").utf8))

  guard depth < maxDepth else { return }
  for child in axChildren(of: element) {
    axDumpTree(element: child, label: label, maxDepth: maxDepth, depth: depth + 1)
  }
}
