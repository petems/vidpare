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
) {
  let hostingView = NSHostingView(rootView: view)
  hostingView.frame = NSRect(origin: .zero, size: size)
  hostingView.appearance = NSAppearance(named: .aqua)
  hostingView.layoutSubtreeIfNeeded()

  // CI runners have different font rendering; relax thresholds to catch
  // layout/color regressions without failing on anti-aliasing differences.
  let effectivePrecision: Float = isCI ? 0.90 : precision
  let effectivePerceptual: Float = isCI ? 0.90 : perceptualPrecision

  assertSnapshot(
    of: hostingView,
    as: .image(
      precision: effectivePrecision,
      perceptualPrecision: effectivePerceptual,
      size: size
    ),
    file: file,
    testName: testName,
    line: line
  )
}
