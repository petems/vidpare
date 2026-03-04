import ApplicationServices
import Foundation

public func axApp(for pid: pid_t) -> AXUIElement {
  AXUIElementCreateApplication(pid)
}

public func axMainWindow(of app: AXUIElement) -> AXUIElement? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &value)
  guard result == .success, let val = value else { return nil }
  // CFTypeRef → AXUIElement requires unsafeBitCast (conditional cast always succeeds for CF types)
  return unsafeBitCast(val, to: AXUIElement.self)
}

public func axWindows(of app: AXUIElement) -> [AXUIElement] {
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

public func axTitle(of element: AXUIElement) -> String? {
  axStringAttribute(kAXTitleAttribute as CFString, of: element)
}

public func axDescription(of element: AXUIElement) -> String? {
  axStringAttribute(kAXDescriptionAttribute as CFString, of: element)
}

public func axRole(of element: AXUIElement) -> String? {
  axStringAttribute(kAXRoleAttribute as CFString, of: element)
}

public func axIdentifier(of element: AXUIElement) -> String? {
  axStringAttribute(kAXIdentifierAttribute as CFString, of: element)
}

public func axChildren(of element: AXUIElement) -> [AXUIElement] {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
  guard result == .success, let array = value as? [AXUIElement] else { return [] }
  return array
}

/// Recursively search the accessibility tree for an element matching the given identifier.
public func findElement(
  withIdentifier identifier: String,
  in element: AXUIElement
) -> AXUIElement? {
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
public func findElements(withRole role: String, in element: AXUIElement) -> [AXUIElement] {
  var results: [AXUIElement] = []
  if axRole(of: element) == role {
    results.append(element)
  }
  for child in axChildren(of: element) {
    results.append(contentsOf: findElements(withRole: role, in: child))
  }
  return results
}

@discardableResult
public func pressButton(_ element: AXUIElement) -> Bool {
  AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
}

/// Check whether an element is enabled (kAXEnabledAttribute).
public func axEnabled(of element: AXUIElement) -> Bool {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &value)
  guard result == .success, let boolVal = value as? Bool else { return false }
  return boolVal
}

/// Read the string value (kAXValueAttribute) of a text field or combo box.
public func axValue(of element: AXUIElement) -> String? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
  guard result == .success else { return nil }
  return value as? String
}

/// Check whether the value attribute of an element is settable (i.e., editable).
public func axIsValueSettable(of element: AXUIElement) -> Bool {
  var settable: DarwinBoolean = false
  let result = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
  return result == .success && settable.boolValue
}

/// Set the string value (kAXValueAttribute) of a text field.
@discardableResult
public func axSetValue(_ value: String, of element: AXUIElement) -> Bool {
  AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef)
    == .success
}

/// Recursively search for the first element matching a role.
public func findElement(withRole role: String, in element: AXUIElement) -> AXUIElement? {
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
public func findElement(
  withRole role: String,
  valueContaining substring: String,
  in element: AXUIElement
) -> AXUIElement? {
  if axRole(of: element) == role, let val = axValue(of: element), val.contains(substring) {
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
public func findButton(titled title: String, in element: AXUIElement) -> AXUIElement? {
  let buttons = findElements(withRole: kAXButtonRole as String, in: element)
  return buttons.first { axTitle(of: $0) == title }
}

/// Read a CGPoint attribute (e.g., kAXPositionAttribute).
public func axPosition(of element: AXUIElement) -> CGPoint? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value)
  guard result == .success, let val = value else { return nil }
  let axVal = unsafeBitCast(val, to: AXValue.self)
  var point = CGPoint.zero
  guard AXValueGetValue(axVal, .cgPoint, &point) else { return nil }
  return point
}

/// Read a CGSize attribute (e.g., kAXSizeAttribute).
public func axSize(of element: AXUIElement) -> CGSize? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value)
  guard result == .success, let val = value else { return nil }
  let axVal = unsafeBitCast(val, to: AXValue.self)
  var size = CGSize.zero
  guard AXValueGetValue(axVal, .cgSize, &size) else { return nil }
  return size
}

/// Return the screen-space frame (position + size) of an AX element.
public func axFrame(of element: AXUIElement) -> CGRect? {
  guard let position = axPosition(of: element),
    let size = axSize(of: element)
  else { return nil }
  return CGRect(origin: position, size: size)
}

/// Simulate a mouse drag from one screen point to another.
public func simulateDrag(from start: CGPoint, to end: CGPoint, steps: Int = 10) {
  let normalizedSteps = max(steps, 1)
  let duration = max(Double(normalizedSteps) * 0.02, 0.2)
  axDrag(from: start, to: end, duration: duration)
}

/// Wait for a condition to become true, polling at intervals.
public func waitFor(
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
