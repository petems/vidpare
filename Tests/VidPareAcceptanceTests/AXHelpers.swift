import ApplicationServices
import Foundation

func axApp(for pid: pid_t) -> AXUIElement {
  AXUIElementCreateApplication(pid)
}

func axMainWindow(of app: AXUIElement) -> AXUIElement? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &value)
  guard result == .success, let val = value else { return nil }
  // CFTypeRef → AXUIElement requires unsafeBitCast (conditional cast always succeeds for CF types)
  return unsafeBitCast(val, to: AXUIElement.self)
}

func axWindows(of app: AXUIElement) -> [AXUIElement] {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
  guard result == .success, let array = value as? [AXUIElement] else { return [] }
  return array
}

private func axStringAttribute(_ attribute: CFString, of element: AXUIElement) -> String? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, attribute, &value)
  guard result == .success else { return nil }
  return value as? String
}

func axTitle(of element: AXUIElement) -> String? {
  axStringAttribute(kAXTitleAttribute as CFString, of: element)
}

func axDescription(of element: AXUIElement) -> String? {
  axStringAttribute(kAXDescriptionAttribute as CFString, of: element)
}

func axRole(of element: AXUIElement) -> String? {
  axStringAttribute(kAXRoleAttribute as CFString, of: element)
}

func axIdentifier(of element: AXUIElement) -> String? {
  axStringAttribute(kAXIdentifierAttribute as CFString, of: element)
}

func axChildren(of element: AXUIElement) -> [AXUIElement] {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
  guard result == .success, let array = value as? [AXUIElement] else { return [] }
  return array
}

/// Recursively search the accessibility tree for an element matching the given identifier.
func findElement(withIdentifier identifier: String, in element: AXUIElement) -> AXUIElement? {
  if axIdentifier(of: element) == identifier {
    return element
  }
  for child in axChildren(of: element) {
    if let found = findElement(withIdentifier: identifier, in: child) {
      return found
    }
  }
  return nil
}

/// Recursively search for all elements matching a role.
func findElements(withRole role: String, in element: AXUIElement) -> [AXUIElement] {
  var results: [AXUIElement] = []
  if axRole(of: element) == role {
    results.append(element)
  }
  for child in axChildren(of: element) {
    results.append(contentsOf: findElements(withRole: role, in: child))
  }
  return results
}

func pressButton(_ element: AXUIElement) -> Bool {
  AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
}

/// Read the string value (kAXValueAttribute) of a text field or combo box.
func axValue(of element: AXUIElement) -> String? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
  guard result == .success else { return nil }
  return value as? String
}

/// Check whether the value attribute of an element is settable (i.e., editable).
func axIsValueSettable(of element: AXUIElement) -> Bool {
  var settable: DarwinBoolean = false
  let result = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
  return result == .success && settable.boolValue
}

/// Set the string value (kAXValueAttribute) of a text field.
@discardableResult
func axSetValue(_ value: String, of element: AXUIElement) -> Bool {
  AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef) == .success
}

/// Recursively search for the first element matching a role.
func findElement(withRole role: String, in element: AXUIElement) -> AXUIElement? {
  if axRole(of: element) == role {
    return element
  }
  for child in axChildren(of: element) {
    if let found = findElement(withRole: role, in: child) {
      return found
    }
  }
  return nil
}

/// Return the sheet attached to a window, if any.
func axSheet(of window: AXUIElement) -> AXUIElement? {
  for child in axChildren(of: window) where axRole(of: child) == "AXSheet" {
    return child
  }
  return nil
}

/// Recursively search for an element matching a role whose value contains a substring.
func findElement(
  withRole role: String,
  valueContaining substring: String,
  in element: AXUIElement
) -> AXUIElement? {
  if axRole(of: element) == role,
     let val = axValue(of: element),
     val.contains(substring) {
    return element
  }
  for child in axChildren(of: element) {
    if let found = findElement(withRole: role, valueContaining: substring, in: child) {
      return found
    }
  }
  return nil
}

/// Find a button by its title text.
func findButton(titled title: String, in element: AXUIElement) -> AXUIElement? {
  let buttons = findElements(withRole: kAXButtonRole as String, in: element)
  return buttons.first { axTitle(of: $0) == title }
}

/// Return the screen-space frame (position + size) of an AX element.
func axFrame(of element: AXUIElement) -> CGRect? {
  var posValue: CFTypeRef?
  var sizeValue: CFTypeRef?
  guard
    AXUIElementCopyAttributeValue(
      element, kAXPositionAttribute as CFString, &posValue
    ) == .success,
    AXUIElementCopyAttributeValue(
      element, kAXSizeAttribute as CFString, &sizeValue
    ) == .success
  else { return nil }
  var position = CGPoint.zero
  var size = CGSize.zero
  // swiftlint:disable:next force_cast
  guard AXValueGetValue(posValue as! AXValue, .cgPoint, &position) else { return nil }
  // swiftlint:disable:next force_cast
  guard AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
  return CGRect(origin: position, size: size)
}

/// Simulate a mouse drag from one screen point to another.
func simulateDrag(from start: CGPoint, to end: CGPoint, steps: Int = 10) {
  let source = CGEventSource(stateID: .combinedSessionState)

  CGEvent(
    mouseEventSource: source,
    mouseType: .leftMouseDown,
    mouseCursorPosition: start,
    mouseButton: .left
  )?.post(tap: .cghidEventTap)
  Thread.sleep(forTimeInterval: 0.05)

  for step in 1...steps {
    let fraction = CGFloat(step) / CGFloat(steps)
    let point = CGPoint(
      x: start.x + (end.x - start.x) * fraction,
      y: start.y + (end.y - start.y) * fraction
    )
    CGEvent(
      mouseEventSource: source,
      mouseType: .leftMouseDragged,
      mouseCursorPosition: point,
      mouseButton: .left
    )?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.02)
  }

  CGEvent(
    mouseEventSource: source,
    mouseType: .leftMouseUp,
    mouseCursorPosition: end,
    mouseButton: .left
  )?.post(tap: .cghidEventTap)
  Thread.sleep(forTimeInterval: 0.05)
}

/// Wait for a condition to become true, polling at intervals.
func waitFor(
  timeout: TimeInterval = 5.0,
  interval: TimeInterval = 0.25,
  condition: () -> Bool
) -> Bool {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if condition() { return true }
    Thread.sleep(forTimeInterval: interval)
  }
  return false
}
