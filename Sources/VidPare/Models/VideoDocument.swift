import AVFoundation
import AppKit

@Observable
final class VideoDocument {
    let url: URL
    let asset: AVURLAsset
    private(set) var duration: CMTime = .zero
    private(set) var naturalSize: CGSize = .zero
    private(set) var codecName: String = "Unknown"
    private(set) var fileSize: Int64 = 0
    private(set) var fileName: String = ""

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedResolution: String {
        "\(Int(naturalSize.width))×\(Int(naturalSize.height))"
    }

    init(url: URL) {
        self.url = url
        self.asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        self.fileName = url.lastPathComponent
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            self.fileSize = size
        }
    }

    func loadMetadata() async throws {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw VideoDocumentError.noVideoTrack
        }

        self.duration = try await asset.load(.duration)
        self.naturalSize = try await videoTrack.load(.naturalSize)

        let descriptions = try await videoTrack.load(.formatDescriptions)
        if let desc = descriptions.first {
            let codecType = CMFormatDescriptionGetMediaSubType(desc)
            self.codecName = codecType.codecName
        }
    }

    static let supportedTypes: [String] = ["mp4", "mov", "m4v"]

    static func canOpen(url: URL) -> Bool {
        supportedTypes.contains(url.pathExtension.lowercased())
    }
}

enum VideoDocumentError: LocalizedError {
    case noVideoTrack
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "The file does not contain a video track."
        case .unsupportedFormat(let ext):
            return "Unsupported format: .\(ext). VidPare supports MP4, MOV, and M4V files."
        }
    }
}

private extension FourCharCode {
    var codecName: String {
        switch self {
        case kCMVideoCodecType_H264: return "H.264"
        case kCMVideoCodecType_HEVC: return "HEVC (H.265)"
        case kCMVideoCodecType_MPEG4Video: return "MPEG-4"
        default:
            let chars = [
                Character(UnicodeScalar((self >> 24) & 0xFF)!),
                Character(UnicodeScalar((self >> 16) & 0xFF)!),
                Character(UnicodeScalar((self >> 8) & 0xFF)!),
                Character(UnicodeScalar(self & 0xFF)!)
            ]
            return String(chars)
        }
    }
}
