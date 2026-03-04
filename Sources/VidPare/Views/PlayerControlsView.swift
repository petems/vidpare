import AVFoundation
import SwiftUI

struct PlayerControlsView: View {
  let currentTime: CMTime
  let duration: CMTime
  let isPlaying: Bool
  @Bindable var trimState: TrimState

  var onPlayPause: () -> Void
  var onSetInPoint: () -> Void
  var onSetOutPoint: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      primaryRow
      secondaryRow
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
  }

  private var primaryRow: some View {
    HStack(spacing: 12) {
      Button(action: onPlayPause) {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(EditorStyle.accentBlue)
          .frame(width: 28, height: 28)
          .background(
            Circle()
              .fill(EditorStyle.innerLaneBackground)
          )
          .overlay(
            Circle()
              .stroke(EditorStyle.accentBlue.opacity(0.45), lineWidth: 1)
          )
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.space, modifiers: [])
      .accessibilityIdentifier(AccessibilityID.playPauseButton)

      Text(
        "\(TimeFormatter.preciseString(from: currentTime)) / \(TimeFormatter.string(from: duration))"
      )
      .font(.system(size: 18, weight: .medium, design: .rounded))
      .monospacedDigit()
      .foregroundStyle(EditorStyle.textPrimary)

      Spacer(minLength: 0)
    }
  }

  private var secondaryRow: some View {
    HStack(spacing: 8) {
      trimMarkerButton(title: "In", action: onSetInPoint)
        .help("Set in point (I)")
        .accessibilityIdentifier(AccessibilityID.inPointButton)

      Text(TimeFormatter.preciseString(from: trimState.startTime))
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(EditorStyle.textSecondary)

      Text("→")
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(EditorStyle.textSecondary.opacity(0.8))

      Text(TimeFormatter.preciseString(from: trimState.endTime))
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(EditorStyle.textSecondary)

      trimMarkerButton(title: "Out", action: onSetOutPoint)
        .help("Set out point (O)")
        .accessibilityIdentifier(AccessibilityID.outPointButton)

      Spacer(minLength: 0)

      Text("Trim: \(TimeFormatter.shortDuration(from: trimState.duration))")
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(EditorStyle.textSecondary)
    }
  }

  private func trimMarkerButton(title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(EditorStyle.textPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
          Capsule()
            .fill(EditorStyle.innerLaneBackground)
        )
        .overlay(
          Capsule()
            .stroke(EditorStyle.trackBaseline, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
  }
}
