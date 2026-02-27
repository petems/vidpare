import AVFoundation

enum TimeFormatter {
    /// Formats CMTime as "HH:MM:SS" or "MM:SS" for shorter durations
    static func string(from time: CMTime) -> String {
        guard time.isValid, !time.isIndefinite else { return "--:--" }
        let totalSeconds = CMTimeGetSeconds(time)
        guard totalSeconds.isFinite, totalSeconds >= 0 else { return "--:--" }

        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    /// Formats CMTime with fractional seconds "MM:SS.f"
    static func preciseString(from time: CMTime) -> String {
        guard time.isValid, !time.isIndefinite else { return "--:--.--" }
        let totalSeconds = CMTimeGetSeconds(time)
        guard totalSeconds.isFinite, totalSeconds >= 0 else { return "--:--.--" }

        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = totalSeconds.truncatingRemainder(dividingBy: 60)

        if hours > 0 {
            return String(format: "%d:%02d:%05.2f", hours, minutes, seconds)
        } else {
            return String(format: "%d:%05.2f", minutes, seconds)
        }
    }

    /// Formats duration as a short human-readable string like "1m 23s"
    static func shortDuration(from time: CMTime) -> String {
        guard time.isValid, !time.isIndefinite else { return "—" }
        let totalSeconds = CMTimeGetSeconds(time)
        guard totalSeconds.isFinite, totalSeconds >= 0 else { return "—" }

        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        let seconds = Int(totalSeconds) % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}
