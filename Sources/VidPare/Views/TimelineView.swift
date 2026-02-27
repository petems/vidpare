import SwiftUI
import AVFoundation

struct TimelineView: View {
    let thumbnails: [NSImage]
    let duration: CMTime
    let currentTime: CMTime
    @Bindable var trimState: TrimState
    var onSeek: (CMTime) -> Void

    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false

    private var totalSeconds: Double {
        let s = CMTimeGetSeconds(duration)
        return s.isFinite && s > 0 ? s : 1
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height: CGFloat = 56

            ZStack(alignment: .leading) {
                // Thumbnail strip
                thumbnailStrip(width: width, height: height)

                // Dimmed regions outside trim
                dimmedOverlay(width: width, height: height)

                // Playhead
                playhead(width: width, height: height)

                // Trim handles
                trimHandle(isStart: true, width: width, height: height)
                trimHandle(isStart: false, width: width, height: height)
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .onTapGesture { location in
                let fraction = max(0, min(1, location.x / width))
                let time = CMTime(seconds: fraction * totalSeconds, preferredTimescale: 600)
                onSeek(time)
            }
        }
        .frame(height: 56)
    }

    @ViewBuilder
    private func thumbnailStrip(width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            if thumbnails.isEmpty {
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: width, height: height)
            } else {
                ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, image in
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width / CGFloat(thumbnails.count), height: height)
                        .clipped()
                }
            }
        }
        .cornerRadius(6)
    }

    @ViewBuilder
    private func dimmedOverlay(width: CGFloat, height: CGFloat) -> some View {
        let startX = xPosition(for: trimState.startTime, in: width)
        let endX = xPosition(for: trimState.endTime, in: width)

        // Left dim
        Rectangle()
            .fill(Color.black.opacity(0.5))
            .frame(width: max(0, startX), height: height)
            .allowsHitTesting(false)

        // Right dim
        Rectangle()
            .fill(Color.black.opacity(0.5))
            .frame(width: max(0, width - endX), height: height)
            .offset(x: endX)
            .allowsHitTesting(false)

        // Trim border
        Rectangle()
            .strokeBorder(Color.accentColor, lineWidth: 2)
            .frame(width: max(0, endX - startX), height: height)
            .offset(x: startX)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func playhead(width: CGFloat, height: CGFloat) -> some View {
        let x = xPosition(for: currentTime, in: width)
        Rectangle()
            .fill(Color.white)
            .frame(width: 2, height: height + 8)
            .shadow(color: .black.opacity(0.5), radius: 1)
            .offset(x: x - 1)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func trimHandle(isStart: Bool, width: CGFloat, height: CGFloat) -> some View {
        let time = isStart ? trimState.startTime : trimState.endTime
        let x = xPosition(for: time, in: width)

        RoundedRectangle(cornerRadius: 3)
            .fill(Color.accentColor)
            .frame(width: 12, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(width: 2, height: 20)
            )
            .offset(x: isStart ? x - 12 : x)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newX = value.location.x
                        let fraction = max(0, min(1, newX / width))
                        let newTime = CMTime(seconds: fraction * totalSeconds, preferredTimescale: 600)

                        if isStart {
                            let maxStart = CMTimeSubtract(trimState.endTime, CMTime(seconds: 0.1, preferredTimescale: 600))
                            trimState.startTime = min(newTime, maxStart)
                            if CMTimeCompare(trimState.startTime, .zero) < 0 {
                                trimState.startTime = .zero
                            }
                        } else {
                            let minEnd = CMTimeAdd(trimState.startTime, CMTime(seconds: 0.1, preferredTimescale: 600))
                            trimState.endTime = max(newTime, minEnd)
                            if CMTimeCompare(trimState.endTime, duration) > 0 {
                                trimState.endTime = duration
                            }
                        }
                    }
            )
            .cursor(.resizeLeftRight)
    }

    private func xPosition(for time: CMTime, in width: CGFloat) -> CGFloat {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite else { return 0 }
        return CGFloat(seconds / totalSeconds) * width
    }
}

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
