import AVFoundation
import UniformTypeIdentifiers

@Observable
final class TrimState {
    var startTime: CMTime = .zero
    var endTime: CMTime = .zero
    var duration: CMTime {
        let d = CMTimeSubtract(endTime, startTime)
        return CMTimeCompare(d, .zero) > 0 ? d : .zero
    }

    var exportFormat: ExportFormat = .mp4H264
    var qualityPreset: QualityPreset = .passthrough

    func reset(for videoDuration: CMTime) {
        startTime = .zero
        endTime = videoDuration
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
