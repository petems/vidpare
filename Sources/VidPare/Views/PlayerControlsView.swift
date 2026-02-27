import SwiftUI
import AVFoundation

struct PlayerControlsView: View {
    let currentTime: CMTime
    let duration: CMTime
    let isPlaying: Bool
    @Bindable var trimState: TrimState

    var onPlayPause: () -> Void
    var onSetInPoint: () -> Void
    var onSetOutPoint: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Play/Pause
            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])

            // Time display
            Text(TimeFormatter.preciseString(from: currentTime))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Text("/")
                .foregroundStyle(.quaternary)

            Text(TimeFormatter.string(from: duration))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer()

            // Trim info
            HStack(spacing: 8) {
                // In point
                Button(action: onSetInPoint) {
                    Label("In", systemImage: "bracket.square.left.fill")
                        .font(.caption)
                }
                .help("Set in point (I)")

                Text(TimeFormatter.preciseString(from: trimState.startTime))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Text("→")
                    .foregroundStyle(.quaternary)

                Text(TimeFormatter.preciseString(from: trimState.endTime))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                // Out point
                Button(action: onSetOutPoint) {
                    Label("Out", systemImage: "bracket.square.right.fill")
                        .font(.caption)
                }
                .help("Set out point (O)")
            }

            Divider().frame(height: 20)

            // Trim duration
            Text("Trim: \(TimeFormatter.shortDuration(from: trimState.duration))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
