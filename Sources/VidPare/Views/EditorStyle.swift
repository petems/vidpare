import SwiftUI

enum EditorStyle {
  static let panelBackground = Color(hex: 0x1A1C39)
  static let chromeStripBackground = Color(hex: 0x272949)
  static let innerLaneBackground = Color(hex: 0x2B2E50)
  static let trackBaseline = Color(hex: 0x3A3E63)
  static let accentBlue = Color(hex: 0x2F78FF)
  static let textPrimary = Color(hex: 0xC4C9E3)
  static let textSecondary = Color(hex: 0x8E94B6)
  static let trafficRed = Color(hex: 0xFF5F56)
  static let trafficYellow = Color(hex: 0xFFBD2E)
  static let trafficGreen = Color(hex: 0x27C93F)

  static let deckCornerRadius: CGFloat = 12
  static let laneCornerRadius: CGFloat = 8
  static let chromeStripHeight: CGFloat = 38
  static let timelineHeight: CGFloat = 56
  static let timelineTrackHeight: CGFloat = 6
  static let timelineTrackInset: CGFloat = 12
  static let timelineHandleTouchWidth: CGFloat = 12
  static let timelineHandleVisualWidth: CGFloat = 3
  static let timelineHandleHeight: CGFloat = 20
  static let timelinePlayheadWidth: CGFloat = 2
}

extension Color {
  fileprivate init(hex: UInt32, alpha: Double = 1.0) {
    let red = Double((hex >> 16) & 0xFF) / 255
    let green = Double((hex >> 8) & 0xFF) / 255
    let blue = Double(hex & 0xFF) / 255
    self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
  }
}
