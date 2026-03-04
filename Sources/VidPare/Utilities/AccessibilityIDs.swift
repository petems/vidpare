enum AccessibilityID {
  // ContentView
  static let dropTarget = "vidpare.dropTarget"
  static let openFileButton = "vidpare.openFile"
  static let videoEditor = "vidpare.videoEditor"

  // PlayerControlsView
  static let playPauseButton = "vidpare.playPause"
  static let soundToggleButton = "vidpare.soundToggle"
  static let inPointButton = "vidpare.inPoint"
  static let outPointButton = "vidpare.outPoint"

  // TimelineView
  static let timeline = "vidpare.timeline"
  static let startHandle = "vidpare.timeline.startHandle"
  static let endHandle = "vidpare.timeline.endHandle"
  // Legacy aliases kept to avoid breaking existing AX scripts/tests.
  static let trimHandleStart = startHandle
  static let trimHandleEnd = endHandle

  // ExportSheet
  static let exportButton = "vidpare.export.exportButton"
  static let cancelButton = "vidpare.export.cancelButton"
  static let exportToneToggleButton = "vidpare.export.toneToggle"
  static let formatPicker = "vidpare.export.formatPicker"
  static let qualityPicker = "vidpare.export.qualityPicker"
  static let completionView = "vidpare.export.completionView"
  static let doneButton = "vidpare.export.doneButton"

  // Toolbar
  static let toolbarOpen = "vidpare.toolbar.open"
  static let toolbarExport = "vidpare.toolbar.export"
}
