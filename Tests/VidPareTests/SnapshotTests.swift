import AppKit
import AVFoundation
import SnapshotTesting
import SwiftUI
@testable import VidPare
import XCTest

@MainActor
final class SnapshotTests: XCTestCase {

  // MARK: - ContentView

  func testContentView_emptyState() throws {
    try snapshotView(
      ContentView(),
      size: CGSize(width: 1024, height: 768)
    )
  }

  // MARK: - PlayerControlsView

  func testPlayerControls_paused() throws {
    let trimState = TrimState()
    trimState.startTime = .zero
    trimState.endTime = CMTime(seconds: 30, preferredTimescale: 600)

    let view = PlayerControlsView(
      currentTime: CMTime(seconds: 10, preferredTimescale: 600),
      duration: CMTime(seconds: 60, preferredTimescale: 600),
      isPlaying: false,
      trimState: trimState,
      onPlayPause: {},
      onSetInPoint: {},
      onSetOutPoint: {}
    )
    try snapshotView(view, size: CGSize(width: 900, height: 80))
  }

  func testPlayerControls_playing() throws {
    let trimState = TrimState()
    trimState.startTime = .zero
    trimState.endTime = CMTime(seconds: 30, preferredTimescale: 600)

    let view = PlayerControlsView(
      currentTime: CMTime(seconds: 10, preferredTimescale: 600),
      duration: CMTime(seconds: 60, preferredTimescale: 600),
      isPlaying: true,
      trimState: trimState,
      onPlayPause: {},
      onSetInPoint: {},
      onSetOutPoint: {}
    )
    try snapshotView(view, size: CGSize(width: 900, height: 80))
  }

  // MARK: - TimelineView

  func testTimelineView_noThumbnails() throws {
    let trimState = TrimState()
    trimState.startTime = CMTime(seconds: 5, preferredTimescale: 600)
    trimState.endTime = CMTime(seconds: 25, preferredTimescale: 600)

    let view = TimelineView(
      thumbnails: [],
      duration: CMTime(seconds: 30, preferredTimescale: 600),
      currentTime: CMTime(seconds: 10, preferredTimescale: 600),
      trimState: trimState,
      onSeek: { _ in }
    )
    try snapshotView(view, size: CGSize(width: 900, height: 80))
  }

  func testTimelineView_trimAtStart() throws {
    let trimState = TrimState()
    trimState.startTime = .zero
    trimState.endTime = CMTime(seconds: 5, preferredTimescale: 600)

    let view = TimelineView(
      thumbnails: [],
      duration: CMTime(seconds: 30, preferredTimescale: 600),
      currentTime: CMTime(seconds: 2, preferredTimescale: 600),
      trimState: trimState,
      onSeek: { _ in }
    )
    try snapshotView(view, size: CGSize(width: 900, height: 80))
  }

  func testTimelineView_fullRange() throws {
    let trimState = TrimState()
    trimState.startTime = .zero
    trimState.endTime = CMTime(seconds: 30, preferredTimescale: 600)

    let view = TimelineView(
      thumbnails: [],
      duration: CMTime(seconds: 30, preferredTimescale: 600),
      currentTime: CMTime(seconds: 15, preferredTimescale: 600),
      trimState: trimState,
      onSeek: { _ in }
    )
    try snapshotView(view, size: CGSize(width: 900, height: 80))
  }

  // MARK: - ExportSheet

  func testExportSheet_initialState() throws {
    guard let fixtureURL = Bundle.module.url(
      forResource: "sample", withExtension: "mp4"
    ) else {
      throw XCTSkip("Missing fixture: sample.mp4")
    }

    let document = VideoDocument(url: fixtureURL)
    let trimState = TrimState()
    trimState.startTime = .zero
    trimState.endTime = CMTime(seconds: 5, preferredTimescale: 600)

    let view = ExportSheet(
      document: document,
      trimState: trimState,
      videoEngine: VideoEngine(),
      onDismiss: {}
    )
    try snapshotView(view, size: CGSize(width: 420, height: 540))
  }
}
