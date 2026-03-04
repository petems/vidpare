import AppKit
import AVFoundation
import CoreMedia
import Foundation

struct PostProcessor {
  let inputURL: URL
  let outputURL: URL
  let posterURL: URL?
  let targetWidth: Int
  let targetBitrate: Int

  init(
    inputURL: URL,
    outputURL: URL,
    posterURL: URL? = nil,
    targetWidth: Int = 1920,
    targetBitrate: Int = 5_000_000
  ) {
    self.inputURL = inputURL
    self.outputURL = outputURL
    self.posterURL = posterURL
    self.targetWidth = targetWidth
    self.targetBitrate = targetBitrate
  }

  func process() async throws {
    let asset = AVURLAsset(url: inputURL)
    let duration = try await asset.load(.duration)

    guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
      throw PostProcessorError.noVideoTrack
    }

    let naturalSize = try await videoTrack.load(.naturalSize)
    let (composition, videoComposition) = try buildComposition(
      videoTrack: videoTrack, duration: duration, naturalSize: naturalSize)

    try await exportComposition(composition, videoComposition: videoComposition)

    print("  Post-processed video: \(outputURL.path)")
    if let posterURL {
      try await extractPoster(from: outputURL, to: posterURL)
    }
  }

  private func buildComposition(
    videoTrack: AVAssetTrack,
    duration: CMTime,
    naturalSize: CGSize
  ) throws -> (AVMutableComposition, AVMutableVideoComposition) {
    let aspectRatio = naturalSize.height / naturalSize.width
    let targetHeight = Int(CGFloat(targetWidth) * aspectRatio)
    let outputWidth = targetWidth % 2 == 0 ? targetWidth : targetWidth + 1
    let outputHeight = targetHeight % 2 == 0 ? targetHeight : targetHeight + 1

    let trimStart = CMTime(seconds: 0.5, preferredTimescale: 600)
    let trimEnd = CMTimeSubtract(duration, CMTime(seconds: 0.5, preferredTimescale: 600))
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
    instruction.timeRange = CMTimeRange(start: .zero, duration: CMTimeSubtract(trimEnd, trimStart))

    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionTrack)
    let scaleX = CGFloat(outputWidth) / naturalSize.width
    let scaleY = CGFloat(outputHeight) / naturalSize.height
    layerInstruction.setTransform(CGAffineTransform(scaleX: scaleX, y: scaleY), at: .zero)
    instruction.layerInstructions = [layerInstruction]
    videoComposition.instructions = [instruction]

    return (composition, videoComposition)
  }

  private func exportComposition(
    _ composition: AVMutableComposition,
    videoComposition: AVMutableVideoComposition
  ) async throws {
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }
    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    let renderSize = videoComposition.renderSize
    print(
      "  Post-process render size: \(Int(renderSize.width))x\(Int(renderSize.height))")

    // Try with video composition first; fall back to passthrough if -16122 occurs
    if let result = try? await exportWith(
      asset: composition, videoComposition: videoComposition, preset: AVAssetExportPresetHighestQuality
    ) {
      if result { return }
    }

    print("  HighestQuality preset failed, trying without video composition...")
    guard
      let exportSession = AVAssetExportSession(
        asset: composition, presetName: AVAssetExportPresetPassthrough)
    else {
      throw PostProcessorError.exportSessionFailed
    }
    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4

    await exportSession.export()
    guard exportSession.status == .completed else {
      throw exportSession.error ?? PostProcessorError.exportFailed
    }
  }

  private func exportWith(
    asset: AVAsset, videoComposition: AVMutableVideoComposition, preset: String
  ) async throws -> Bool {
    guard
      let exportSession = AVAssetExportSession(asset: asset, presetName: preset)
    else {
      return false
    }
    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.videoComposition = videoComposition

    await exportSession.export()
    if exportSession.status == .completed { return true }
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try? FileManager.default.removeItem(at: outputURL)
    }
    return false
  }

  private func extractPoster(from videoURL: URL, to posterURL: URL) async throws {
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

enum PostProcessorError: Error, CustomStringConvertible {
  case noVideoTrack
  case compositionFailed
  case exportSessionFailed
  case exportFailed
  case posterExtractionFailed

  var description: String {
    switch self {
    case .noVideoTrack: return "No video track found in recording."
    case .compositionFailed: return "Failed to create composition track."
    case .exportSessionFailed: return "Failed to create export session."
    case .exportFailed: return "Export session failed."
    case .posterExtractionFailed: return "Failed to extract poster frame."
    }
  }
}
