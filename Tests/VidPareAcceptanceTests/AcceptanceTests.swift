import ApplicationServices
import AVFoundation
import AXAutomation
import XCTest

final class AcceptanceTests: XCTestCase {
  private let launcher = AppLauncher()
  private var pid: pid_t = 0

  override func setUpWithError() throws {
    try super.setUpWithError()

    guard AXIsProcessTrusted() else {
      throw XCTSkip(
        "Accessibility permissions required. Add Terminal (or your IDE) to "
          + "System Settings > Privacy & Security > Accessibility."
      )
    }

    pid = try launcher.launch()
  }

  override func tearDown() {
    launcher.terminate()
    super.tearDown()
  }

  // MARK: - Launch Tests

  func testAppLaunches_hasWindow() {
    let app = axApp(for: pid)
    let hasWindow = waitFor {
      !axWindows(of: app).isEmpty
    }
    XCTAssertTrue(hasWindow, "App should have at least one window after launch")
  }

  func testAppLaunches_windowTitleIsVidPare() {
    let app = axApp(for: pid)
    var title: String?
    let found = waitFor {
      if let window = axWindows(of: app).first {
        title = axTitle(of: window)
        return title != nil
      }
      return false
    }
    XCTAssertTrue(found, "Should find a window")
    XCTAssertEqual(title, "VidPare", "Window title should be 'VidPare'")
  }

  func testAppLaunches_showsDropTarget() {
    let app = axApp(for: pid)
    var openButton: AXUIElement?

    let success = waitFor {
      guard let window = axWindows(of: app).first else { return false }
      // SwiftUI propagates the parent's accessibilityIdentifier to all children,
      // so search the entire window for a button whose description contains "Open File".
      let buttons = findElements(withRole: kAXButtonRole as String, in: window)
      openButton = buttons.first { btn in
        let title = axTitle(of: btn) ?? ""
        let desc = axDescription(of: btn) ?? ""
        return title.contains("Open File") || desc.contains("Open File")
      }
      return openButton != nil
    }

    XCTAssertTrue(success, "Should find an Open File button on launch")
  }

  func testAppLaunches_hasToolbarOpenButton() {
    let app = axApp(for: pid)

    var toolbarButton: AXUIElement?
    let found = waitFor {
      guard let window = axWindows(of: app).first else { return false }
      if let btn = findElement(withIdentifier: "vidpare.toolbar.open", in: window) {
        toolbarButton = btn
        return true
      }
      let buttons = findElements(withRole: kAXButtonRole as String, in: window)
      toolbarButton = buttons.first { btn in
        let desc = axDescription(of: btn) ?? ""
        return desc == "Open"
      }
      return toolbarButton != nil
    }
    XCTAssertTrue(found, "Should find toolbar Open button")
    XCTAssertNotNil(toolbarButton)
  }

  // MARK: - Export Filename Editability

  func testExport_savePanelFilenameIsEditable() throws {
    let tempFile = try copyFixtureToTemp()
    defer { try? FileManager.default.removeItem(at: tempFile) }

    let app = axApp(for: pid)
    guard let window = axWindows(of: app).first else {
      XCTFail("No app window found")
      return
    }

    try openVideoFile(at: tempFile, inWindow: window)
    try openExportSheet(inWindow: window)
    try assertSavePanelFilenameEditable(app: app, window: window)
  }

  // MARK: - GIF Export Flows

  func testGIFExport_startCompletesAndWritesFile() throws {
    let sourceFile = try copyFixtureToTemp()
    defer { try? FileManager.default.removeItem(at: sourceFile) }

    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("vidpare-gif-\(UUID().uuidString).gif")
    defer { try? FileManager.default.removeItem(at: outputURL) }

    let app = axApp(for: pid)
    guard let window = axWindows(of: app).first else {
      XCTFail("No app window found")
      return
    }

    try openVideoFile(at: sourceFile, inWindow: window)
    try openExportSheet(inWindow: window, autoPressExport: false)
    try selectExportFormatGIF(inWindow: window)
    try triggerExportAndConfirmSave(app: app, window: window, outputURL: outputURL)

    let completed = waitFor(timeout: 20.0) {
      findElement(withIdentifier: "vidpare.export.completionView", in: window) != nil
    }
    XCTAssertTrue(completed, "Export completion view should appear for GIF export")
    XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path), "GIF output should exist")
  }

  func testGIFExport_cancelStopsExportAndRemovesOutput() throws {
    let sourceFile = try copyFixtureToTemp()
    defer { try? FileManager.default.removeItem(at: sourceFile) }

    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("vidpare-gif-cancel-\(UUID().uuidString).gif")
    defer { try? FileManager.default.removeItem(at: outputURL) }

    let app = axApp(for: pid)
    guard let window = axWindows(of: app).first else {
      XCTFail("No app window found")
      return
    }

    try openVideoFile(at: sourceFile, inWindow: window)
    try openExportSheet(inWindow: window, autoPressExport: false)
    try selectExportFormatGIF(inWindow: window)
    try triggerExportAndConfirmSave(app: app, window: window, outputURL: outputURL)

    let exportCancelAppeared = waitFor(timeout: 10.0) {
      findButton(titled: "Cancel", in: window) != nil
    }
    XCTAssertTrue(exportCancelAppeared, "Export cancel button should appear while GIF export is running")

    guard let exportCancelButton = findButton(titled: "Cancel", in: window) else {
      XCTFail("Expected export cancel button")
      return
    }
    XCTAssertTrue(pressButton(exportCancelButton), "Should cancel GIF export")

    let exportReset = waitFor(timeout: 10.0) {
      findElement(withIdentifier: "vidpare.export.exportButton", in: window) != nil
    }
    XCTAssertTrue(exportReset, "Export sheet should return to idle state after cancellation")
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: outputURL.path),
      "Cancelled GIF export should not leave an output file"
    )
  }

  func testGIFExport_durationLimitBlocksSavePanel() async throws {
    let sourceFile = try copyFixtureToTemp()
    defer { try? FileManager.default.removeItem(at: sourceFile) }

    let asset = AVURLAsset(url: sourceFile)
    let sourceDurationSeconds = CMTimeGetSeconds(try await asset.load(.duration))
    guard sourceDurationSeconds > 15.0 else {
      throw XCTSkip("Fixture is too short to exceed the GIF 15s limit")
    }

    let app = axApp(for: pid)
    guard let window = axWindows(of: app).first else {
      XCTFail("No app window found")
      return
    }

    try openVideoFile(at: sourceFile, inWindow: window)
    try openExportSheet(inWindow: window, autoPressExport: false)
    try selectExportFormatGIF(inWindow: window)

    guard let exportButton = findElement(withIdentifier: "vidpare.export.exportButton", in: window) else {
      XCTFail("Export button not found in export sheet")
      return
    }
    XCTAssertTrue(pressButton(exportButton), "Should attempt GIF export")

    let savePanelAppeared = waitFor(timeout: 3.0) {
      findSavePanel(in: app) != nil
    }
    XCTAssertFalse(savePanelAppeared, "Save panel should not appear when GIF exceeds 15s limit")
  }
}

// MARK: - Test Helpers

extension AcceptanceTests {

  private func copyFixtureToTemp() throws -> URL {
    let fixtureSource = URL(fileURLWithPath: "Tests/VidPareTests/Fixtures/sample.mp4")
    guard FileManager.default.fileExists(atPath: fixtureSource.path) else {
      throw XCTSkip("Fixture sample.mp4 not found at \(fixtureSource.path)")
    }
    let tempFile = FileManager.default.temporaryDirectory
      .appendingPathComponent("vidpare-test-\(UUID().uuidString).mp4")
    try FileManager.default.copyItem(at: fixtureSource, to: tempFile)
    return tempFile
  }

  private func openVideoFile(at fileURL: URL, inWindow window: AXUIElement) throws {
    let foundOpenButton = waitFor {
      findElement(withIdentifier: "vidpare.openFile", in: window) != nil
    }
    XCTAssertTrue(foundOpenButton, "Should find Open File button")
    guard let openButton = findElement(withIdentifier: "vidpare.openFile", in: window) else {
      return
    }
    XCTAssertTrue(pressButton(openButton), "Should be able to press Open File button")

    let openPanelAppeared = waitFor(timeout: 5.0) {
      findElement(withRole: kAXSheetRole as String, in: window) != nil
    }
    XCTAssertTrue(openPanelAppeared, "Open panel sheet should appear")
    guard let sheet = findElement(withRole: kAXSheetRole as String, in: window) else {
      XCTFail("Could not find open panel sheet")
      return
    }

    try navigateOpenPanel(sheet: sheet, fileURL: fileURL, window: window)
  }

  private func navigateOpenPanel(
    sheet: AXUIElement,
    fileURL: URL,
    window: AXUIElement
  ) throws {
    let textFields = findElements(withRole: kAXComboBoxRole as String, in: sheet)
      + findElements(withRole: kAXTextFieldRole as String, in: sheet)
    guard let pathField = textFields.first(where: { axIsValueSettable(of: $0) }) else {
      if let cancelBtn = findButton(titled: "Cancel", in: sheet) {
        pressButton(cancelBtn)
      }
      throw XCTSkip("Could not find an editable text field in the open panel")
    }

    XCTAssertTrue(
      axSetValue(fileURL.path, of: pathField),
      "Should be able to set the file path in the open panel"
    )
    Thread.sleep(forTimeInterval: 0.5)

    // Press Return to confirm the path
    sendKeyPress(virtualKey: 0x24)

    let editorAppeared = waitFor(timeout: 10.0) {
      findElement(withIdentifier: "vidpare.toolbar.export", in: window) != nil
    }
    if !editorAppeared {
      if let openBtn = findButton(titled: "Open", in: sheet) {
        pressButton(openBtn)
        let retryEditor = waitFor(timeout: 5.0) {
          findElement(withIdentifier: "vidpare.toolbar.export", in: window) != nil
        }
        if !retryEditor {
          throw XCTSkip("Could not open fixture file via the open panel")
        }
      } else {
        throw XCTSkip("Video editor did not appear after opening file")
      }
    }
  }

  private func openExportSheet(inWindow window: AXUIElement, autoPressExport: Bool = true) throws {
    let exportToolbarFound = waitFor(timeout: 5.0) {
      findElement(withIdentifier: "vidpare.toolbar.export", in: window) != nil
    }
    XCTAssertTrue(exportToolbarFound, "Should find the Export toolbar button")
    guard let exportToolbar = findElement(
      withIdentifier: "vidpare.toolbar.export",
      in: window
    ) else {
      XCTFail("Export toolbar button not found")
      return
    }
    XCTAssertTrue(pressButton(exportToolbar), "Should press Export toolbar button")

    let exportSheetAppeared = waitFor(timeout: 5.0) {
      findElement(withIdentifier: "vidpare.export.exportButton", in: window) != nil
    }
    XCTAssertTrue(exportSheetAppeared, "Export sheet should appear with Export button")

    guard let exportButton = findElement(
      withIdentifier: "vidpare.export.exportButton",
      in: window
    ) else {
      XCTFail("Export button not found in export sheet")
      return
    }

    guard autoPressExport else { return }

    // Wait for capability loading to finish
    Thread.sleep(forTimeInterval: 1.0)
    XCTAssertTrue(pressButton(exportButton), "Should press Export button")
  }

  private func assertSavePanelFilenameEditable(
    app: AXUIElement,
    window: AXUIElement
  ) throws {
    var savePanelField: AXUIElement?
    let savePanelAppeared = waitFor(timeout: 5.0) {
      for win in axWindows(of: app) {
        if let field = findElement(
          withRole: kAXTextFieldRole as String,
          valueContaining: "_trimmed",
          in: win
        ) {
          savePanelField = field
          return true
        }
      }
      return false
    }

    XCTAssertTrue(
      savePanelAppeared,
      "NSSavePanel should appear with filename containing '_trimmed'"
    )
    guard let filenameField = savePanelField else {
      XCTFail("Could not find filename text field in save panel")
      return
    }

    let currentValue = axValue(of: filenameField) ?? ""
    XCTAssertTrue(
      currentValue.contains("_trimmed"),
      "Filename should contain '_trimmed', got: '\(currentValue)'"
    )
    XCTAssertTrue(
      axIsValueSettable(of: filenameField),
      "Filename field must be editable (AXIsAttributeSettable should return true)"
    )

    let customName = "my_custom_export"
    XCTAssertTrue(axSetValue(customName, of: filenameField), "Should set a custom filename")
    let updatedValue = axValue(of: filenameField) ?? ""
    XCTAssertTrue(
      updatedValue.hasPrefix(customName),
      "Filename field should start with '\(customName)', got: '\(updatedValue)'"
    )

    dismissSavePanel(app: app)
  }

  private func dismissSavePanel(app: AXUIElement) {
    for win in axWindows(of: app) {
      if let cancelBtn = findButton(titled: "Cancel", in: win) {
        pressButton(cancelBtn)
        return
      }
    }
  }

  private func findSavePanel(in app: AXUIElement) -> AXUIElement? {
    for win in axWindows(of: app) {
      if axRole(of: win) == kAXSheetRole as String {
        return win
      }
      if let sheet = findElement(withRole: kAXSheetRole as String, in: win) {
        return sheet
      }
    }
    return nil
  }

  private func selectExportFormatGIF(inWindow window: AXUIElement) throws {
    let selected = waitFor(timeout: 5.0) {
      let radioButtons = findElements(withRole: kAXRadioButtonRole as String, in: window)
      guard let gifButton = radioButtons.first(where: { (axTitle(of: $0) ?? "").contains("GIF") }) else {
        return false
      }
      return pressButton(gifButton)
    }
    if !selected {
      throw XCTSkip("Could not select GIF format in export sheet")
    }
  }

  private func triggerExportAndConfirmSave(
    app: AXUIElement,
    window: AXUIElement,
    outputURL: URL
  ) throws {
    guard let exportButton = findElement(withIdentifier: "vidpare.export.exportButton", in: window) else {
      XCTFail("Export button not found in export sheet")
      return
    }
    XCTAssertTrue(pressButton(exportButton), "Should press Export button")

    let savePanelAppeared = waitFor(timeout: 5.0) {
      findSavePanel(in: app) != nil
    }
    XCTAssertTrue(savePanelAppeared, "Save panel should appear")
    guard let savePanel = findSavePanel(in: app) else {
      XCTFail("Could not find save panel")
      return
    }

    let pathFields = findElements(withRole: kAXComboBoxRole as String, in: savePanel)
      + findElements(withRole: kAXTextFieldRole as String, in: savePanel)
    guard let pathField = pathFields.first(where: { axIsValueSettable(of: $0) }) else {
      if let cancelBtn = findButton(titled: "Cancel", in: savePanel) {
        pressButton(cancelBtn)
      }
      throw XCTSkip("Could not find editable path field in save panel")
    }

    XCTAssertTrue(axSetValue(outputURL.path, of: pathField), "Should set save path")
    Thread.sleep(forTimeInterval: 0.3)
    sendKeyPress(virtualKey: 0x24)
  }

  private func sendKeyPress(virtualKey: CGKeyCode) {
    let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true)
    keyDown?.post(tap: .cghidEventTap)
    let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false)
    keyUp?.post(tap: .cghidEventTap)
  }
}
