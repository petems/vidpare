import AVFoundation
import Observation
import UniformTypeIdentifiers

@Observable
final class TrimState {
    var startTime: CMTime = .zero
    var endTime: CMTime = .zero
    var duration: CMTime {
        let durationDelta = CMTimeSubtract(endTime, startTime)
        return CMTimeCompare(durationDelta, .zero) > 0 ? durationDelta : .zero
    }

    var exportFormat: ExportFormat = .mp4H264
    var qualityPreset: QualityPreset = .passthrough
    var gifSettings = GIFExportSettings()

    func reset(for videoDuration: CMTime) {
        let seconds = CMTimeGetSeconds(videoDuration)
        let sanitized = (videoDuration.isValid && !videoDuration.isIndefinite && seconds.isFinite && seconds > 0)
            ? videoDuration
            : .zero
        startTime = .zero
        endTime = sanitized
    }

    func isAtOrPastEnd(_ time: CMTime) -> Bool {
        CMTimeCompare(time, endTime) >= 0
    }

    var trimRange: CMTimeRange {
        let clampedEnd = CMTimeCompare(endTime, startTime) > 0 ? endTime : startTime
        return CMTimeRange(start: startTime, end: clampedEnd)
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case mp4H264 = "MP4 (H.264)"
    case movH264 = "MOV (H.264)"
    case mp4HEVC = "MP4 (HEVC/H.265)"
    case gif = "GIF"

    var id: String { rawValue }

    var fileType: AVFileType {
        switch self {
        case .mp4H264, .mp4HEVC: return .mp4
        case .movH264: return .mov
        case .gif: return .gif
        }
    }

    var fileExtension: String {
        switch self {
        case .mp4H264, .mp4HEVC: return "mp4"
        case .movH264: return "mov"
        case .gif: return "gif"
        }
    }

    var contentType: UTType {
        switch self {
        case .mp4H264, .mp4HEVC: return .mpeg4Movie
        case .movH264: return .quickTimeMovie
        case .gif: return .gif
        }
    }

    var isHEVC: Bool {
        self == .mp4HEVC
    }

    var containerLabel: String {
        switch self {
        case .movH264:
            return "MOV"
        case .gif:
            return "GIF"
        case .mp4H264, .mp4HEVC:
            return "MP4"
        }
    }

    static func passthroughContainerFormat(sourceFileType: AVFileType?, sourceIsHEVC: Bool) -> ExportFormat {
        guard let sourceFileType else {
            return sourceIsHEVC ? .mp4HEVC : .mp4H264
        }

        switch sourceFileType {
        case .mov:
            return .movH264
        case .m4v:
            return sourceIsHEVC ? .mp4HEVC : .mp4H264
        default:
            return sourceIsHEVC ? .mp4HEVC : .mp4H264
        }
    }
}

struct GIFExportSettings: Equatable {
    static let maxDurationSeconds: TimeInterval = 15
    var frameRate: GIFFrameRate = .fps12
    var scale: GIFScale = .full
}

enum GIFFrameRate: Int, CaseIterable, Identifiable {
    case fps8 = 8
    case fps12 = 12
    case fps15 = 15

    var id: Int { rawValue }

    var label: String {
        "\(rawValue) FPS"
    }
}

enum GIFScale: Double, CaseIterable, Identifiable {
    case full = 1.0
    case medium = 0.75
    case small = 0.5

    var id: Double { rawValue }

    var label: String {
        switch self {
        case .full: return "100%"
        case .medium: return "75%"
        case .small: return "50%"
        }
    }
}

extension AVFileType {
    static let gif = AVFileType(rawValue: "com.compuserve.gif")
}

enum QualityPreset: String, CaseIterable, Identifiable {
    case passthrough = "Passthrough (Fastest)"
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var id: String { rawValue }

    var exportPreset: String {
        switch self {
        case .passthrough: return AVAssetExportPresetPassthrough
        case .high: return AVAssetExportPresetHighestQuality
        case .medium: return AVAssetExportPresetMediumQuality
        case .low: return AVAssetExportPresetLowQuality
        }
    }

    var isPassthrough: Bool {
        self == .passthrough
    }
}
