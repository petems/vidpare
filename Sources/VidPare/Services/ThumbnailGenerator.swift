import AVFoundation
import AppKit

final class ThumbnailGenerator {
    private let asset: AVURLAsset
    private var generator: AVAssetImageGenerator

    init(asset: AVURLAsset) {
        self.asset = asset
        self.generator = AVAssetImageGenerator(asset: asset)
        self.generator.appliesPreferredTrackTransform = true
        self.generator.maximumSize = CGSize(width: 160, height: 90)
        self.generator.requestedTimeToleranceBefore = .zero
        self.generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
    }

    func generateThumbnails(count: Int) async throws -> [NSImage] {
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        guard totalSeconds > 0 else { return [] }

        let clampedCount = max(10, min(count, 60))
        let interval = totalSeconds / Double(clampedCount)

        let times: [NSValue] = (0..<clampedCount).map { i in
            let time = CMTime(seconds: Double(i) * interval, preferredTimescale: 600)
            return NSValue(time: time)
        }

        return try await withCheckedThrowingContinuation { continuation in
            var images: [Int: NSImage] = [:]
            var currentIndex = 0
            let expectedCount = times.count

            generator.generateCGImagesAsynchronously(forTimes: times) { _, cgImage, _, result, error in
                let index = currentIndex
                currentIndex += 1

                if let cgImage = cgImage, result == .succeeded {
                    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    images[index] = nsImage
                }

                if currentIndex == expectedCount {
                    let sorted = (0..<expectedCount).compactMap { images[$0] }
                    continuation.resume(returning: sorted)
                }
            }
        }
    }

    func cancelGeneration() {
        generator.cancelAllCGImageGeneration()
    }

    static func thumbnailCount(forDuration seconds: Double) -> Int {
        // ~1 thumbnail per 2 seconds, clamped between 10 and 60
        let count = Int(seconds / 2.0)
        return max(10, min(count, 60))
    }
}
