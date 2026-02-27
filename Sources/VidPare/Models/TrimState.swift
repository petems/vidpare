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

    var id: String { rawValue }

    var fileType: AVFileType {
        switch self {
        case .mp4H264, .mp4HEVC: return .mp4
        case .movH264: return .mov
        }
    }

    var fileExtension: String {
        switch self {
        case .mp4H264, .mp4HEVC: return "mp4"
        case .movH264: return "mov"
        }
    }

    var contentType: UTType {
        switch self {
        case .mp4H264, .mp4HEVC: return .mpeg4Movie
        case .movH264: return .quickTimeMovie
        }
    }

    var isHEVC: Bool {
        self == .mp4HEVC
    }

    var containerLabel: String {
        switch fileType {
        case .mov:
            return "MOV"
        default:
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
