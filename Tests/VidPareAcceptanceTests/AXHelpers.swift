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

func axTitle(of element: AXUIElement) -> String? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
  guard result == .success else { return nil }
  return value as? String
}

func axRole(of element: AXUIElement) -> String? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
  guard result == .success else { return nil }
  return value as? String
}

func axIdentifier(of element: AXUIElement) -> String? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &value)
  guard result == .success else { return nil }
  return value as? String
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
