import AppKit
import AVFoundation

final class ThumbnailGenerator {
    private let asset: AVURLAsset
    private var generator: AVAssetImageGenerator

    init(asset: AVURLAsset) {
        self.asset = asset
        self.generator = AVAssetImageGenerator(asset: asset)
        self.generator.appliesPreferredTrackTransform = true
        self.generator.maximumSize = CGSize(width: 160, height: 90)
        self.generator.requestedTimeToleranceBefore = .zero
        self.generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
    }

    func generateThumbnails(count: Int) async throws -> [NSImage] {
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)
        guard totalSeconds > 0 else { return [] }

        let clampedCount = max(10, min(count, 60))
        let interval = totalSeconds / Double(clampedCount)
        let indexedTimes: [(index: Int, time: CMTime)] = (0..<clampedCount).map { index in
            let time = CMTime(seconds: Double(index) * interval, preferredTimescale: 600)
            return (index, time)
        }
        let requestTimes = indexedTimes.map { NSValue(time: $0.time) }
        let timeIndexByValue = Dictionary(uniqueKeysWithValues: indexedTimes.map { ($0.time.value, $0.index) })

        return try await withCheckedThrowingContinuation { continuation in
            let stateQueue = DispatchQueue(label: "vidpare.thumbnail-generator.state")
            var images: [Int: NSImage] = [:]
            var completedCount = 0
            let expectedCount = requestTimes.count
            var didResume = false
            var firstError: Error?

            generator.generateCGImagesAsynchronously(forTimes: requestTimes) { requestedTime, cgImage, _, result, error in
                stateQueue.async {
                    guard !didResume else { return }

                    if let cgImage = cgImage,
                       result == .succeeded,
                       let index = timeIndexByValue[requestedTime.value] {
                        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                        images[index] = nsImage
                    } else if result == .failed, firstError == nil {
                        firstError = error ?? ThumbnailGenerationError.failed
                    } else if result == .cancelled, firstError == nil {
                        firstError = ThumbnailGenerationError.cancelled
                    }

                    completedCount += 1
                    if completedCount == expectedCount {
                        didResume = true
                        if images.isEmpty, let firstError {
                            continuation.resume(throwing: firstError)
                            return
                        }

                        let sorted = (0..<expectedCount).compactMap { images[$0] }
                        continuation.resume(returning: sorted)
                    }
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

enum ThumbnailGenerationError: LocalizedError {
    case failed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .failed:
            return "Thumbnail generation failed."
        case .cancelled:
            return "Thumbnail generation was cancelled."
        }
    }
}
