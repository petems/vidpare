import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

@MainActor
func snapshotView<V: View>(
  _ view: V,
  size: CGSize,
  precision: Float = 0.98,
  file: StaticString = #file,
  testName: String = #function,
  line: UInt = #line
) {
  let hostingView = NSHostingView(rootView: view)
  hostingView.frame = NSRect(origin: .zero, size: size)
  hostingView.appearance = NSAppearance(named: .aqua)
  hostingView.layoutSubtreeIfNeeded()

  assertSnapshot(
    of: hostingView,
    as: .image(precision: precision, size: size),
    file: file,
    testName: testName,
    line: line
  )
}
