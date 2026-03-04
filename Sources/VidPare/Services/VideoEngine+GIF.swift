import AVFoundation
import ImageIO
import UniformTypeIdentifiers

extension VideoEngine {
    nonisolated static func renderGIF(
        asset: AVURLAsset,
        trimRange: CMTimeRange,
        outputURL: URL,
        settings: GIFExportSettings,
        progressHandler: @escaping @Sendable (Double) async -> Void
    ) async throws {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw ExportError.exportFailed("The selected file does not contain a video track.")
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let orientedSize = orientedVideoSize(naturalSize: naturalSize, transform: preferredTransform)

        let targetSize = CGSize(
            width: max(1, floor(orientedSize.width * settings.scale.rawValue)),
            height: max(1, floor(orientedSize.height * settings.scale.rawValue))
        )

        let frameCount = gifFrameCount(
            duration: trimRange.duration,
            frameRate: settings.frameRate.rawValue
        )

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else {
            throw ExportError.exportFailed("Failed to create GIF destination.")
        }

        let globalProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, globalProperties as CFDictionary)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = targetSize

        let delayTime = 1.0 / Double(settings.frameRate.rawValue)

        for frameIndex in 0..<frameCount {
            try Task.checkCancellation()

            let offsetSeconds = Double(frameIndex) / Double(settings.frameRate.rawValue)
            let frameTime = CMTimeAdd(
                trimRange.start,
                CMTime(seconds: offsetSeconds, preferredTimescale: 600)
            )

            let image = try generator.copyCGImage(at: frameTime, actualTime: nil)

            let frameProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delayTime
                ]
            ]

            autoreleasepool {
                CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
            }

            await progressHandler(Double(frameIndex + 1) / Double(frameCount))
        }

        try Task.checkCancellation()

        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.exportFailed("Failed to finalize GIF file.")
        }
    }
}

private extension VideoEngine {
    nonisolated static func gifFrameCount(duration: CMTime, frameRate: Int) -> Int {
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else { return 1 }
        return max(1, Int(floor(seconds * Double(frameRate))))
    }

    nonisolated static func orientedVideoSize(
        naturalSize: CGSize,
        transform: CGAffineTransform
    ) -> CGSize {
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        return CGSize(
            width: abs(transformedRect.width),
            height: abs(transformedRect.height)
        )
    }
}
