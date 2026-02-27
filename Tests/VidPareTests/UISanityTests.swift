import AppKit
import AVFoundation
import SwiftUI
@testable import VidPare
import XCTest

@MainActor
final class UISanityTests: XCTestCase {
    func testContentViewRendersInHostingView() {
        let hostingView = NSHostingView(rootView: ContentView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 1024, height: 768)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(hostingView.fittingSize.width, 0)
        XCTAssertGreaterThan(hostingView.fittingSize.height, 0)
    }

    func testPlayerControlsViewRendersInHostingView() {
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
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 80)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(hostingView.fittingSize.width, 0)
        XCTAssertGreaterThan(hostingView.fittingSize.height, 0)
    }

    func testTimelineViewRendersInHostingView() {
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
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 80)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(hostingView.fittingSize.width, 0)
        XCTAssertGreaterThan(hostingView.fittingSize.height, 0)
    }
}
