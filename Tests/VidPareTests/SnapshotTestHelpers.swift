import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

/// True when running inside a CI environment (GitHub Actions, etc.)
var isCI: Bool {
  ProcessInfo.processInfo.environment["CI"] != nil
}

@MainActor
func snapshotView<V: View>(
  _ view: V,
  size: CGSize,
  precision: Float = 0.98,
  perceptualPrecision: Float = 0.98,
  file: StaticString = #file,
  testName: String = #function,
  line: UInt = #line
) throws {
  if isCI {
    throw XCTSkip("Snapshot tests are local-only (rendering varies too much across machines)")
  }

  let hostingView = NSHostingView(rootView: view)
  hostingView.frame = NSRect(origin: .zero, size: size)
  hostingView.appearance = NSAppearance(named: .aqua)
  hostingView.layoutSubtreeIfNeeded()

  assertSnapshot(
    of: hostingView,
    as: .image(
      precision: precision,
      perceptualPrecision: perceptualPrecision,
      size: size
    ),
    file: file,
    testName: testName,
    line: line
  )
}
