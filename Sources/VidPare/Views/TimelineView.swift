import AVFoundation
import SwiftUI

struct TimelineView: View {
  let thumbnails: [NSImage]
  let duration: CMTime
  let currentTime: CMTime
  @Bindable var trimState: TrimState
  var onSeek: (CMTime) -> Void

  private static let timelineCoordinateSpace = "timeline"

  private var totalSeconds: Double {
    let durationSeconds = CMTimeGetSeconds(duration)
    return durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : 1
  }

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      let height = EditorStyle.timelineHeight

      ZStack(alignment: .leading) {
        laneBackground(width: width, height: height)
        thumbnailStrip(width: width, height: height)
        dimmedOverlay(width: width, height: height)
        trimTrack(width: width)
        playhead(width: width, height: height)
        trimHandle(isStart: true, width: width, height: height)
        trimHandle(isStart: false, width: width, height: height)
      }
      .frame(height: height)
      .coordinateSpace(name: Self.timelineCoordinateSpace)
      .contentShape(Rectangle())
      .onTapGesture { location in
        let fraction = max(0, min(1, location.x / width))
        let time = CMTime(seconds: fraction * totalSeconds, preferredTimescale: 600)
        onSeek(time)
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier(AccessibilityID.timeline)
    }
    .frame(height: EditorStyle.timelineHeight)
  }

  @ViewBuilder
  private func laneBackground(width: CGFloat, height: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: EditorStyle.laneCornerRadius, style: .continuous)
      .fill(EditorStyle.innerLaneBackground)
      .frame(width: width, height: height)
      .overlay(
        RoundedRectangle(cornerRadius: EditorStyle.laneCornerRadius, style: .continuous)
          .stroke(EditorStyle.trackBaseline, lineWidth: 1)
      )
  }

  @ViewBuilder
  private func thumbnailStrip(width: CGFloat, height: CGFloat) -> some View {
    Group {
      if thumbnails.isEmpty {
        RoundedRectangle(cornerRadius: EditorStyle.laneCornerRadius, style: .continuous)
          .fill(EditorStyle.trackBaseline.opacity(0.35))
      } else {
        HStack(spacing: 0) {
          ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, image in
            Image(nsImage: image)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: width / CGFloat(thumbnails.count), height: height)
              .clipped()
          }
        }
      }
    }
    .frame(width: width, height: height)
    .overlay(EditorStyle.panelBackground.opacity(0.52))
    .clipShape(RoundedRectangle(cornerRadius: EditorStyle.laneCornerRadius, style: .continuous))
    .allowsHitTesting(false)
  }

  @ViewBuilder
  private func trimTrack(width: CGFloat) -> some View {
    let trackWidth = max(0, width - EditorStyle.timelineTrackInset * 2)
    let startX = xPosition(for: trimState.startTime, in: trackWidth)
    let endX = xPosition(for: trimState.endTime, in: trackWidth)

    ZStack(alignment: .leading) {
      Capsule()
        .fill(EditorStyle.trackBaseline)
      Capsule()
        .fill(EditorStyle.accentBlue.opacity(0.42))
        .frame(width: max(0, endX - startX))
        .offset(x: startX)
    }
    .frame(width: trackWidth, height: EditorStyle.timelineTrackHeight)
    .offset(x: EditorStyle.timelineTrackInset)
    .allowsHitTesting(false)
  }

  @ViewBuilder
  private func dimmedOverlay(width: CGFloat, height: CGFloat) -> some View {
    let startX = xPosition(for: trimState.startTime, in: width)
    let endX = xPosition(for: trimState.endTime, in: width)

    Rectangle()
      .fill(EditorStyle.panelBackground.opacity(0.42))
      .frame(width: max(0, startX), height: height)
      .allowsHitTesting(false)

    Rectangle()
      .fill(EditorStyle.panelBackground.opacity(0.42))
      .frame(width: max(0, width - endX), height: height)
      .offset(x: endX)
      .allowsHitTesting(false)

    RoundedRectangle(cornerRadius: EditorStyle.laneCornerRadius - 2, style: .continuous)
      .strokeBorder(EditorStyle.accentBlue.opacity(0.7), lineWidth: 1)
      .frame(width: max(0, endX - startX), height: height - 10)
      .offset(x: startX)
      .allowsHitTesting(false)
  }

  @ViewBuilder
  private func playhead(width: CGFloat, height: CGFloat) -> some View {
    let x = xPosition(for: currentTime, in: width)
    RoundedRectangle(cornerRadius: 1)
      .fill(EditorStyle.accentBlue)
      .frame(width: EditorStyle.timelinePlayheadWidth, height: height - 16)
      .shadow(color: .black.opacity(0.35), radius: 1)
      .offset(x: x - EditorStyle.timelinePlayheadWidth / 2)
      .allowsHitTesting(false)
  }

  @ViewBuilder
  private func trimHandle(isStart: Bool, width: CGFloat, height: CGFloat) -> some View {
    let time = isStart ? trimState.startTime : trimState.endTime
    let x = xPosition(for: time, in: width)

    RoundedRectangle(cornerRadius: 2)
      .fill(.clear)
      .frame(width: EditorStyle.timelineHandleTouchWidth, height: height)
      .overlay(
        RoundedRectangle(cornerRadius: 2)
          .fill(EditorStyle.accentBlue)
          .frame(
            width: EditorStyle.timelineHandleVisualWidth,
            height: EditorStyle.timelineHandleHeight
          )
      )
      .contentShape(Rectangle())
      .gesture(
        DragGesture(coordinateSpace: .named(Self.timelineCoordinateSpace))
          .onChanged { value in
            let newX = value.location.x
            let fraction = max(0, min(1, newX / width))
            let newTime = CMTime(seconds: fraction * totalSeconds, preferredTimescale: 600)

            if isStart {
              let maxStart = CMTimeSubtract(
                trimState.endTime,
                CMTime(seconds: 0.1, preferredTimescale: 600)
              )
              trimState.startTime = min(newTime, maxStart)
              if CMTimeCompare(trimState.startTime, .zero) < 0 {
                trimState.startTime = .zero
              }
            } else {
              let minEnd = CMTimeAdd(
                trimState.startTime,
                CMTime(seconds: 0.1, preferredTimescale: 600)
              )
              trimState.endTime = max(newTime, minEnd)
              if CMTimeCompare(trimState.endTime, duration) > 0 {
                trimState.endTime = duration
              }
            }
          }
      )
      .offset(x: Self.trimHandleOffset(isStart: isStart, x: x, width: width))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(isStart ? "Start trim handle" : "End trim handle")
      .accessibilityIdentifier(
        isStart ? AccessibilityID.trimHandleStart : AccessibilityID.trimHandleEnd
      )
      .cursor(.resizeLeftRight)
  }

  private func xPosition(for time: CMTime, in width: CGFloat) -> CGFloat {
    Self.xPosition(for: time, totalSeconds: totalSeconds, in: width)
  }

  static func xPosition(for time: CMTime, totalSeconds: Double, in width: CGFloat) -> CGFloat {
    let seconds = CMTimeGetSeconds(time)
    guard seconds.isFinite, totalSeconds > 0 else { return 0 }
    let clamped = min(max(seconds, 0), totalSeconds)
    return CGFloat(clamped / totalSeconds) * width
  }

  static func trimHandleOffset(isStart: Bool, x: CGFloat, width: CGFloat) -> CGFloat {
    let handleWidth = EditorStyle.timelineHandleTouchWidth
    return isStart ? max(0, x - handleWidth) : min(width - handleWidth, x)
  }
}

extension View {
  fileprivate func cursor(_ cursor: NSCursor) -> some View {
    onHover { inside in
      if inside {
        cursor.push()
      } else {
        NSCursor.pop()
      }
    }
  }
}
