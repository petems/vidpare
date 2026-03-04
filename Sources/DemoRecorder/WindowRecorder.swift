import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

final class WindowRecorder: NSObject, SCStreamOutput {
  private var stream: SCStream?
  private var assetWriter: AVAssetWriter?
  private var videoInput: AVAssetWriterInput?
  private var isFirstSample = true
  private var isRecording = false
  private let outputURL: URL

  init(outputURL: URL) {
    self.outputURL = outputURL
    super.init()
  }

  func start(windowID: CGWindowID, fps: Int = 30) async throws {
    let content = try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: true)
    guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
      throw RecorderError.windowNotFound
    }

    let filter = SCContentFilter(desktopIndependentWindow: window)

    // Derive pixel dimensions from the filter's actual content rect (macOS 14+)
    let contentSize = filter.contentRect.size
    let scale = CGFloat(filter.pointPixelScale)
    // H.264 requires even dimensions
    let pixelWidth = Int(contentSize.width * scale) & ~1
    let pixelHeight = Int(contentSize.height * scale) & ~1
    print("  Recording dimensions: \(pixelWidth)x\(pixelHeight) (content: \(contentSize), scale: \(scale))")

    let config = SCStreamConfiguration()
    config.width = pixelWidth
    config.height = pixelHeight
    config.scalesToFit = true
    config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.showsCursor = true
    config.capturesAudio = false
    config.ignoreShadowsSingleWindow = true
    config.shouldBeOpaque = true

    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }

    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

    let videoSettings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: pixelWidth,
      AVVideoHeightKey: pixelHeight,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 16_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
      ]
    ]

    let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    input.expectsMediaDataInRealTime = true
    writer.add(input)

    self.assetWriter = writer
    self.videoInput = input
    self.isFirstSample = true

    writer.startWriting()

    let captureStream = SCStream(filter: filter, configuration: config, delegate: nil)
    try captureStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
    try await captureStream.startCapture()

    self.stream = captureStream
    self.isRecording = true
  }

  func stop() async throws -> URL {
    guard isRecording else { throw RecorderError.notRecording }
    isRecording = false

    if let stream {
      do {
        try await stream.stopCapture()
      } catch {
        // Stream may already be stopped if the target window closed
      }
      self.stream = nil
    }

    guard let writer = assetWriter else { throw RecorderError.notRecording }

    videoInput?.markAsFinished()
    await writer.finishWriting()

    if writer.status == .failed {
      throw writer.error ?? RecorderError.writeFailed
    }

    return outputURL
  }

  // MARK: - SCStreamOutput

  func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .screen, isRecording else { return }
    guard sampleBuffer.isValid else { return }

    guard let writer = assetWriter, let input = videoInput else { return }
    guard writer.status == .writing else { return }

    if isFirstSample {
      writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
      isFirstSample = false
    }

    if input.isReadyForMoreMediaData {
      input.append(sampleBuffer)
    }
  }
}

enum RecorderError: Error, CustomStringConvertible {
  case windowNotFound
  case notRecording
  case writeFailed

  var description: String {
    switch self {
    case .windowNotFound: return "Could not find the target window for recording."
    case .notRecording: return "Recorder is not currently recording."
    case .writeFailed: return "AVAssetWriter failed to write the recording."
    }
  }
}
