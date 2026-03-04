import AppKit
@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

struct PostProcessor {
  private static let exportCoordinator = ExportCoordinator()

  private struct CompositionBuildResult {
    let composition: AVMutableComposition
    let videoComposition: AVMutableVideoComposition
    let compositionTrack: AVAssetTrack
  }

  let inputURL: URL
  let outputURL: URL
  let posterURL: URL?
  let targetWidth: Int
  let targetBitrate: Int

  /// Creates a post-processor that trims, scales, and re-encodes a raw recording.
  init(
    inputURL: URL,
    outputURL: URL,
    posterURL: URL? = nil,
    targetWidth: Int = 1920,
    targetBitrate: Int = 5_000_000
  ) {
    precondition(targetWidth > 0, "targetWidth must be greater than 0")
    precondition(targetBitrate > 0, "targetBitrate must be greater than 0")
    self.inputURL = inputURL
    self.outputURL = outputURL
    self.posterURL = posterURL
    self.targetWidth = targetWidth
    self.targetBitrate = targetBitrate
  }

  /// Runs the full post-processing pipeline and optionally extracts a poster frame.
  func process() async throws {
    let securityScopedAccess = SecurityScopedAccess()
    let buildResult = try await withSecurityScopedResourceAccess(
      securityScopedAccess,
      urls: [inputURL, inputURL.deletingLastPathComponent()]
    ) {
      try await Self.exportCoordinator.withFileLoad {
        let asset = AVURLAsset(url: inputURL)
        let duration = try await asset.load(.duration)

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
          throw PostProcessorError.noVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        return try buildComposition(
          videoTrack: videoTrack,
          duration: duration,
          naturalSize: naturalSize,
          preferredTransform: preferredTransform
        )
      }
    }

    try await Self.exportCoordinator.withExport {
      try await exportComposition(
        buildResult.composition,
        videoComposition: buildResult.videoComposition,
        compositionTrack: buildResult.compositionTrack,
        securityScopedAccess: securityScopedAccess
      )
    }

    print("  Post-processed video: \(outputURL.path)")
    if let posterURL {
      try await extractPoster(
        from: outputURL,
        to: posterURL,
        securityScopedAccess: securityScopedAccess
      )
    }
  }

  /// Wraps post-processing with reference-counted security-scoped resource acquisition.
  private func withSecurityScopedResourceAccess<T>(
    _ access: SecurityScopedAccess,
    urls: [URL],
    operation: () async throws -> T
  ) async throws -> T {
    access.acquire(urls: urls)
    defer { access.release(urls: urls) }
    return try await operation()
  }

  /// Builds a trimmed composition and matching video composition for scaling/rendering.
  private func buildComposition(
    videoTrack: AVAssetTrack,
    duration: CMTime,
    naturalSize: CGSize,
    preferredTransform: CGAffineTransform
  ) throws -> CompositionBuildResult {
    let aspectRatio = naturalSize.height / naturalSize.width
    let targetHeight = Int(CGFloat(targetWidth) * aspectRatio)
    let outputWidth = targetWidth % 2 == 0 ? targetWidth : targetWidth + 1
    let outputHeight = targetHeight % 2 == 0 ? targetHeight : targetHeight + 1

    let trimMargin = CMTime(seconds: 0.5, preferredTimescale: 600)
    let trimStart: CMTime
    let trimEnd: CMTime

    if CMTimeCompare(duration, CMTime(seconds: 1.5, preferredTimescale: 600)) <= 0 {
      trimStart = .zero
      trimEnd = duration
    } else {
      trimStart = trimMargin
      trimEnd = CMTimeSubtract(duration, trimMargin)
    }
    let trimRange = CMTimeRange(start: trimStart, end: trimEnd)

    let composition = AVMutableComposition()
    guard
      let compositionTrack = composition.addMutableTrack(
        withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    else {
      throw PostProcessorError.compositionFailed
    }
    try compositionTrack.insertTimeRange(trimRange, of: videoTrack, at: .zero)

    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = CGSize(width: outputWidth, height: outputHeight)
    videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(
      start: .zero, duration: CMTimeSubtract(trimEnd, trimStart))

    let layerInstruction = AVMutableVideoCompositionLayerInstruction(
      assetTrack: compositionTrack)
    let scaleX = CGFloat(outputWidth) / naturalSize.width
    let scaleY = CGFloat(outputHeight) / naturalSize.height
    let scaleTransform = CGAffineTransform(scaleX: scaleX, y: scaleY)
    let combinedTransform = preferredTransform.concatenating(scaleTransform)
    layerInstruction.setTransform(combinedTransform, at: .zero)
    instruction.layerInstructions = [layerInstruction]
    videoComposition.instructions = [instruction]

    return CompositionBuildResult(
      composition: composition,
      videoComposition: videoComposition,
      compositionTrack: compositionTrack
    )
  }

  /// Exports the composed timeline to `outputURL`, cleaning up partial output on failure.
  private func exportComposition(
    _ composition: AVMutableComposition,
    videoComposition: AVMutableVideoComposition,
    compositionTrack: AVAssetTrack,
    securityScopedAccess: SecurityScopedAccess
  ) async throws {
    try await withSecurityScopedResourceAccess(
      securityScopedAccess,
      urls: [outputURL, outputURL.deletingLastPathComponent()]
    ) {
      if FileManager.default.fileExists(atPath: outputURL.path) {
        try FileManager.default.removeItem(at: outputURL)
      }
      try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

      let renderSize = videoComposition.renderSize
      print(
        "  Post-process render size: \(Int(renderSize.width))x\(Int(renderSize.height))")
      print("  Post-process target bitrate: \(targetBitrate) bps")

      do {
        try await exportWithBitrate(
          asset: composition,
          videoTrack: compositionTrack,
          videoComposition: videoComposition
        )
      } catch {
        if FileManager.default.fileExists(atPath: outputURL.path) {
          try? FileManager.default.removeItem(at: outputURL)
        }
        throw error
      }
    }
  }

  /// Re-encodes the composition with an explicit target bitrate using reader/writer APIs.
  private func exportWithBitrate(
    asset: AVAsset,
    videoTrack: AVAssetTrack,
    videoComposition: AVMutableVideoComposition
  ) async throws {
    let (reader, readerOutput) = try setupReader(
      asset: asset,
      videoTrack: videoTrack,
      videoComposition: videoComposition
    )
    let (writer, writerInput) = try setupWriter(renderSize: videoComposition.renderSize)

    try startPipeline(reader: reader, writer: writer)
    try await pumpVideoSamples(
      reader: reader,
      readerOutput: readerOutput,
      writer: writer,
      writerInput: writerInput
    )
    try validateReaderCompletion(reader)
    try await finishWriter(writer: writer, writerInput: writerInput)
  }

  /// Configures an asset reader output that applies the supplied video composition.
  private func setupReader(
    asset: AVAsset,
    videoTrack: AVAssetTrack,
    videoComposition: AVMutableVideoComposition
  ) throws -> (AVAssetReader, AVAssetReaderVideoCompositionOutput) {
    let reader = try AVAssetReader(asset: asset)
    let readerOutput = AVAssetReaderVideoCompositionOutput(
      videoTracks: [videoTrack],
      videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
    )
    readerOutput.videoComposition = videoComposition
    guard reader.canAdd(readerOutput) else {
      throw PostProcessorError.exportFailed
    }
    reader.add(readerOutput)
    return (reader, readerOutput)
  }

  /// Configures an H.264 MP4 writer/input pair for the target render size and bitrate.
  private func setupWriter(
    renderSize: CGSize
  ) throws -> (AVAssetWriter, AVAssetWriterInput) {
    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    let width = Int(renderSize.width)
    let height = Int(renderSize.height)
    let videoSettings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: targetBitrate,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
      ]
    ]
    let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    writerInput.expectsMediaDataInRealTime = false
    guard writer.canAdd(writerInput) else {
      throw PostProcessorError.exportFailed
    }
    writer.add(writerInput)
    return (writer, writerInput)
  }

  /// Starts reading and writing sessions and aligns the writer session start time.
  private func startPipeline(reader: AVAssetReader, writer: AVAssetWriter) throws {
    guard reader.startReading() else {
      throw reader.error ?? PostProcessorError.exportFailed
    }
    guard writer.startWriting() else {
      throw writer.error ?? PostProcessorError.exportFailed
    }
    writer.startSession(atSourceTime: .zero)
  }

  /// Copies composed video samples from reader to writer until EOF or terminal state.
  private func pumpVideoSamples(
    reader: AVAssetReader,
    readerOutput: AVAssetReaderVideoCompositionOutput,
    writer: AVAssetWriter,
    writerInput: AVAssetWriterInput
  ) async throws {
    var stalledNanoseconds: UInt64 = 0
    let maxStallNanoseconds: UInt64 = 60_000_000_000

    while reader.status == .reading {
      if writer.status == .failed {
        throw writer.error ?? PostProcessorError.exportFailed
      }
      if writer.status == .cancelled {
        throw writer.error ?? PostProcessorError.exportFailed
      }

      if writerInput.isReadyForMoreMediaData {
        stalledNanoseconds = 0
        if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
          if !writerInput.append(sampleBuffer) {
            throw writer.error ?? PostProcessorError.exportFailed
          }
          continue
        }
        break
      }
      try await Task.sleep(nanoseconds: 1_000_000)  // 1ms backoff while the writer catches up.
      stalledNanoseconds += 1_000_000
      if stalledNanoseconds >= maxStallNanoseconds {
        throw PostProcessorError.exportFailed
      }
    }
  }

  /// Validates the reader reached a non-failed terminal state.
  private func validateReaderCompletion(_ reader: AVAssetReader) throws {
    if reader.status == .failed {
      throw reader.error ?? PostProcessorError.exportFailed
    }
    if reader.status == .cancelled {
      throw PostProcessorError.exportFailed
    }
  }

  /// Finalizes writer input and verifies the writer completed successfully.
  private func finishWriter(writer: AVAssetWriter, writerInput: AVAssetWriterInput) async throws {
    writerInput.markAsFinished()
    await writer.finishWriting()
    if writer.status != .completed {
      throw writer.error ?? PostProcessorError.exportFailed
    }
  }

  /// Extracts a JPEG poster from the midpoint of the processed video.
  private func extractPoster(
    from videoURL: URL,
    to posterURL: URL,
    securityScopedAccess: SecurityScopedAccess
  ) async throws {
    try await withSecurityScopedResourceAccess(
      securityScopedAccess,
      urls: [videoURL, videoURL.deletingLastPathComponent(), posterURL, posterURL.deletingLastPathComponent()]
    ) {
      try await Self.exportCoordinator.withFileLoad {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let posterTime = CMTimeMultiplyByFloat64(duration, multiplier: 0.5)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: targetWidth * 2, height: 0)

        let (cgImage, _) = try await generator.image(at: posterTime)
        let nsImage = NSImage(
          cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

        guard let tiffData = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        else {
          throw PostProcessorError.posterExtractionFailed
        }

        try jpegData.write(to: posterURL)
        print("  Poster frame: \(posterURL.path)")
      }
    }
  }
}

enum PostProcessorError: Error, CustomStringConvertible {
  case noVideoTrack
  case compositionFailed
  case exportFailed
  case exportInProgress
  case fileLoadBlockedDuringExport
  case posterExtractionFailed

  var description: String {
    switch self {
    case .noVideoTrack: return "No video track found in recording."
    case .compositionFailed: return "Failed to create composition track."
    case .exportFailed: return "Export session failed."
    case .exportInProgress: return "Another export is already in progress."
    case .fileLoadBlockedDuringExport:
      return "File loading is blocked while an export is active."
    case .posterExtractionFailed: return "Failed to extract poster frame."
    }
  }
}

/// Coordinates post-processing so callers cannot load/export files concurrently.
private actor ExportCoordinator {
  private var activeExports = 0
  private var activeFileLoads = 0

  func withExport<T>(_ operation: () async throws -> T) async throws -> T {
    guard activeExports == 0 else {
      throw PostProcessorError.exportInProgress
    }
    guard activeFileLoads == 0 else {
      throw PostProcessorError.fileLoadBlockedDuringExport
    }
    activeExports += 1
    defer { activeExports -= 1 }
    return try await operation()
  }

  func withFileLoad<T>(_ operation: () async throws -> T) async throws -> T {
    guard activeExports == 0 else {
      throw PostProcessorError.fileLoadBlockedDuringExport
    }
    activeFileLoads += 1
    defer { activeFileLoads -= 1 }
    return try await operation()
  }
}

/// Reference-counted security-scoped URL access used by post-processing file I/O.
private final class SecurityScopedAccess {
  private struct Entry {
    var refCount: Int
    let url: URL
    let started: Bool
  }

  private var entries: [String: Entry] = [:]

  func acquire(urls: [URL]) {
    for url in urls {
      let standardized = url.standardizedFileURL
      let key = standardized.path
      if var entry = entries[key] {
        entry.refCount += 1
        entries[key] = entry
        continue
      }
      let started = standardized.startAccessingSecurityScopedResource()
      entries[key] = Entry(refCount: 1, url: standardized, started: started)
    }
  }

  func release(urls: [URL]) {
    for url in urls {
      release(key: url.standardizedFileURL.path)
    }
  }

  private func release(key: String) {
    guard var entry = entries[key] else { return }
    entry.refCount -= 1
    if entry.refCount == 0 {
      if entry.started {
        entry.url.stopAccessingSecurityScopedResource()
      }
      entries.removeValue(forKey: key)
      return
    }
    entries[key] = entry
  }
}
