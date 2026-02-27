import AVFoundation
import UniformTypeIdentifiers
@testable import VidPare
import XCTest

final class VideoEngineTests: XCTestCase {

    func testEstimatePassthrough() {
        let fileSize: Int64 = 100_000_000 // 100 MB
        let duration = CMTime(seconds: 60, preferredTimescale: 600)
        let trimRange = CMTimeRange(
            start: CMTime(seconds: 10, preferredTimescale: 600),
            end: CMTime(seconds: 40, preferredTimescale: 600)
        )

        let estimate = VideoEngine.estimateOutputSize(
            fileSize: fileSize,
            videoDuration: duration,
            trimRange: trimRange,
            quality: .passthrough
        )

        // 30s of 60s = 50% of 100MB = 50MB
        XCTAssertEqual(estimate, 50_000_000)
    }

    func testEstimateHigh() {
        let fileSize: Int64 = 100_000_000
        let duration = CMTime(seconds: 60, preferredTimescale: 600)
        let trimRange = CMTimeRange(
            start: CMTime(seconds: 0, preferredTimescale: 600),
            end: CMTime(seconds: 30, preferredTimescale: 600)
        )

        let estimate = VideoEngine.estimateOutputSize(
            fileSize: fileSize,
            videoDuration: duration,
            trimRange: trimRange,
            quality: .high
        )

        // 50% trim * 0.9 quality factor = 45MB
        XCTAssertEqual(estimate, 45_000_000)
    }

    func testEstimateMedium() {
        let fileSize: Int64 = 100_000_000
        let duration = CMTime(seconds: 100, preferredTimescale: 600)
        let trimRange = CMTimeRange(
            start: CMTime(seconds: 0, preferredTimescale: 600),
            end: CMTime(seconds: 100, preferredTimescale: 600)
        )

        let estimate = VideoEngine.estimateOutputSize(
            fileSize: fileSize,
            videoDuration: duration,
            trimRange: trimRange,
            quality: .medium
        )

        // Full duration * 0.5 quality factor = 50MB
        XCTAssertEqual(estimate, 50_000_000)
    }

    func testEstimateLow() {
        let fileSize: Int64 = 200_000_000
        let duration = CMTime(seconds: 120, preferredTimescale: 600)
        let trimRange = CMTimeRange(
            start: CMTime(seconds: 60, preferredTimescale: 600),
            end: CMTime(seconds: 120, preferredTimescale: 600)
        )

        let estimate = VideoEngine.estimateOutputSize(
            fileSize: fileSize,
            videoDuration: duration,
            trimRange: trimRange,
            quality: .low
        )

        // 50% trim * 0.25 quality factor = 25MB
        XCTAssertEqual(estimate, 25_000_000)
    }

    func testEstimateZeroDuration() {
        let estimate = VideoEngine.estimateOutputSize(
            fileSize: 100_000_000,
            videoDuration: .zero,
            trimRange: CMTimeRange(start: .zero, end: .zero),
            quality: .passthrough
        )

        XCTAssertEqual(estimate, 0)
    }

    func testEstimateIndefiniteDuration() {
        let estimate = VideoEngine.estimateOutputSize(
            fileSize: 100_000_000,
            videoDuration: .indefinite,
            trimRange: CMTimeRange(start: .zero, end: CMTime(seconds: 10, preferredTimescale: 600)),
            quality: .passthrough
        )
        XCTAssertEqual(estimate, 0)
    }

    func testEstimateInvalidDuration() {
        let estimate = VideoEngine.estimateOutputSize(
            fileSize: 100_000_000,
            videoDuration: .invalid,
            trimRange: CMTimeRange(start: .zero, end: CMTime(seconds: 10, preferredTimescale: 600)),
            quality: .passthrough
        )
        XCTAssertEqual(estimate, 0)
    }

    func testEstimateNegativeTrimRange() {
        let estimate = VideoEngine.estimateOutputSize(
            fileSize: 100_000_000,
            videoDuration: CMTime(seconds: 60, preferredTimescale: 600),
            trimRange: CMTimeRange(
                start: CMTime(seconds: 40, preferredTimescale: 600),
                end: CMTime(seconds: 10, preferredTimescale: 600)
            ),
            quality: .passthrough
        )
        // Negative trim results in clamped ratio of 0
        XCTAssertEqual(estimate, 0)
    }

    func testTrimStateReset() {
        let state = TrimState()
        let duration = CMTime(seconds: 60, preferredTimescale: 600)
        state.reset(for: duration)

        XCTAssertEqual(CMTimeCompare(state.startTime, .zero), 0)
        XCTAssertEqual(CMTimeCompare(state.endTime, duration), 0)
    }

    func testTrimStateResetWithInvalidDuration() {
        let state = TrimState()
        state.startTime = CMTime(seconds: 10, preferredTimescale: 600)
        state.endTime = CMTime(seconds: 50, preferredTimescale: 600)

        state.reset(for: .invalid)
        XCTAssertEqual(CMTimeCompare(state.startTime, .zero), 0)
        XCTAssertEqual(CMTimeCompare(state.endTime, .zero), 0)
    }

    func testTrimStateResetWithIndefiniteDuration() {
        let state = TrimState()
        state.reset(for: .indefinite)
        XCTAssertEqual(CMTimeCompare(state.endTime, .zero), 0)
    }

    func testTrimStateResetWithNegativeDuration() {
        let state = TrimState()
        state.reset(for: CMTime(seconds: -5, preferredTimescale: 600))
        XCTAssertEqual(CMTimeCompare(state.endTime, .zero), 0)
    }

    func testTrimStateDuration() {
        let state = TrimState()
        state.startTime = CMTime(seconds: 10, preferredTimescale: 600)
        state.endTime = CMTime(seconds: 40, preferredTimescale: 600)

        let expectedDuration = CMTime(seconds: 30, preferredTimescale: 600)
        XCTAssertEqual(CMTimeCompare(state.duration, expectedDuration), 0)
    }

    func testExportFormatFileTypes() {
        XCTAssertEqual(ExportFormat.mp4H264.fileType, .mp4)
        XCTAssertEqual(ExportFormat.mp4H264.fileExtension, "mp4")
        XCTAssertEqual(ExportFormat.movH264.fileType, .mov)
        XCTAssertEqual(ExportFormat.movH264.fileExtension, "mov")
        XCTAssertEqual(ExportFormat.mp4HEVC.fileType, .mp4)
        XCTAssertEqual(ExportFormat.mp4HEVC.fileExtension, "mp4")
        XCTAssertTrue(ExportFormat.mp4HEVC.isHEVC)
        XCTAssertFalse(ExportFormat.mp4H264.isHEVC)
    }

    func testQualityPresetValues() {
        XCTAssertEqual(QualityPreset.passthrough.exportPreset, AVAssetExportPresetPassthrough)
        XCTAssertEqual(QualityPreset.high.exportPreset, AVAssetExportPresetHighestQuality)
        XCTAssertEqual(QualityPreset.medium.exportPreset, AVAssetExportPresetMediumQuality)
        XCTAssertEqual(QualityPreset.low.exportPreset, AVAssetExportPresetLowQuality)
        XCTAssertTrue(QualityPreset.passthrough.isPassthrough)
        XCTAssertFalse(QualityPreset.high.isPassthrough)
    }

    func testThumbnailCount() {
        // Short video: should get minimum of 10
        XCTAssertEqual(ThumbnailGenerator.thumbnailCount(forDuration: 5), 10)

        // Medium video: 1 per 2 seconds
        XCTAssertEqual(ThumbnailGenerator.thumbnailCount(forDuration: 40), 20)

        // Long video: capped at 60
        XCTAssertEqual(ThumbnailGenerator.thumbnailCount(forDuration: 300), 60)
    }

    func testExportFormatContentTypes() {
        XCTAssertEqual(ExportFormat.mp4H264.contentType, .mpeg4Movie)
        XCTAssertEqual(ExportFormat.mp4HEVC.contentType, .mpeg4Movie)
        XCTAssertEqual(ExportFormat.movH264.contentType, .quickTimeMovie)
    }

    func testTrimStateInvalidOrderDuration() {
        let state = TrimState()
        state.startTime = CMTime(seconds: 40, preferredTimescale: 600)
        state.endTime = CMTime(seconds: 10, preferredTimescale: 600)

        XCTAssertEqual(CMTimeCompare(state.duration, .zero), 0)
    }

    func testTrimStateInvalidOrderTrimRange() {
        let state = TrimState()
        state.startTime = CMTime(seconds: 40, preferredTimescale: 600)
        state.endTime = CMTime(seconds: 10, preferredTimescale: 600)

        XCTAssertEqual(CMTimeCompare(state.trimRange.duration, .zero), 0)
    }

    func testVideoDocumentRejectsUnsupportedFormat() async {
        let url = URL(fileURLWithPath: "/tmp/test.mkv")
        let doc = VideoDocument(url: url)

        do {
            try await doc.loadMetadata()
            XCTFail("Expected unsupportedFormat error")
        } catch let error as VideoDocumentError {
            if case .unsupportedFormat(let ext) = error {
                XCTAssertEqual(ext, "mkv")
            } else {
                XCTFail("Expected unsupportedFormat, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - VideoEngine state

    @MainActor func testVideoEngineIsNotExportingByDefault() {
        let engine = VideoEngine()
        XCTAssertFalse(engine.isExporting)
    }

    @MainActor func testVideoEngineProgressStartsAtZero() {
        let engine = VideoEngine()
        XCTAssertEqual(engine.progress, 0)
    }

    // MARK: - VideoEngine.effectiveQuality

    func testEffectiveQuality_hevcPassthrough_nonHEVCSource() {
        let result = VideoEngine.effectiveQuality(format: .mp4HEVC, quality: .passthrough, sourceIsHEVC: false)
        XCTAssertEqual(result, .high)
    }

    func testEffectiveQuality_hevcPassthrough_hevcSource() {
        let result = VideoEngine.effectiveQuality(format: .mp4HEVC, quality: .passthrough, sourceIsHEVC: true)
        XCTAssertEqual(result, .passthrough)
    }

    func testEffectiveQuality_h264Passthrough() {
        let result = VideoEngine.effectiveQuality(format: .mp4H264, quality: .passthrough, sourceIsHEVC: false)
        XCTAssertEqual(result, .passthrough)
    }

    func testEffectiveQuality_hevcHigh() {
        let result = VideoEngine.effectiveQuality(format: .mp4HEVC, quality: .high, sourceIsHEVC: false)
        XCTAssertEqual(result, .high)
    }

    // MARK: - TrimState.isAtOrPastEnd

    func testIsAtOrPastEnd_beforeEnd() {
        let state = TrimState()
        state.startTime = .zero
        state.endTime = CMTime(seconds: 10, preferredTimescale: 600)
        XCTAssertFalse(state.isAtOrPastEnd(CMTime(seconds: 5, preferredTimescale: 600)))
    }

    func testIsAtOrPastEnd_atEnd() {
        let state = TrimState()
        state.startTime = .zero
        state.endTime = CMTime(seconds: 10, preferredTimescale: 600)
        XCTAssertTrue(state.isAtOrPastEnd(CMTime(seconds: 10, preferredTimescale: 600)))
    }

    func testIsAtOrPastEnd_pastEnd() {
        let state = TrimState()
        state.startTime = .zero
        state.endTime = CMTime(seconds: 10, preferredTimescale: 600)
        XCTAssertTrue(state.isAtOrPastEnd(CMTime(seconds: 15, preferredTimescale: 600)))
    }

    func testIsAtOrPastEnd_atStart() {
        let state = TrimState()
        state.startTime = .zero
        state.endTime = CMTime(seconds: 10, preferredTimescale: 600)
        XCTAssertFalse(state.isAtOrPastEnd(.zero))
    }

    func testVideoDocumentRejectsNoVideoTrack() async throws {
        let uid = UUID().uuidString
        let m4aURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_audio_\(uid).m4a")
        let mp4URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_audio_\(uid).mp4")
        defer {
            try? FileManager.default.removeItem(at: m4aURL)
            try? FileManager.default.removeItem(at: mp4URL)
        }

        // Create a valid audio-only M4A via macOS `say` command
        let sayProcess = Process()
        sayProcess.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        sayProcess.arguments = ["-o", m4aURL.path, "--data-format=aac", "test"]
        try sayProcess.run()
        sayProcess.waitUntilExit()
        XCTAssertEqual(sayProcess.terminationStatus, 0, "say command failed")

        // Convert to MP4 container via afconvert so VideoDocument.canOpen passes
        let convertProcess = Process()
        convertProcess.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        convertProcess.arguments = [m4aURL.path, mp4URL.path, "-d", "aac", "-f", "mp4f"]
        try convertProcess.run()
        convertProcess.waitUntilExit()
        XCTAssertEqual(convertProcess.terminationStatus, 0, "afconvert command failed")

        let doc = VideoDocument(url: mp4URL)
        do {
            try await doc.loadMetadata()
            XCTFail("Expected noVideoTrack error")
        } catch let error as VideoDocumentError {
            if case .noVideoTrack = error {
                // Expected
            } else {
                XCTFail("Expected noVideoTrack, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - FourCharCode.codecName

    func testCodecNameKnownCodecs() {
        XCTAssertEqual(kCMVideoCodecType_H264.codecName, "H.264")
        XCTAssertEqual(kCMVideoCodecType_HEVC.codecName, "HEVC (H.265)")
        XCTAssertEqual(kCMVideoCodecType_MPEG4Video.codecName, "MPEG-4")
    }

    func testCodecNameUnknownCodec() {
        // FourCharCode for 'test' = 0x74657374
        let unknown: FourCharCode = 0x74657374
        let name = unknown.codecName
        XCTAssertEqual(name.count, 4)
        XCTAssertEqual(name, "test")
    }

    func testVideoDocumentSupportedTypes() {
        XCTAssertTrue(VideoDocument.canOpen(url: URL(fileURLWithPath: "/test.mp4")))
        XCTAssertTrue(VideoDocument.canOpen(url: URL(fileURLWithPath: "/test.MOV")))
        XCTAssertTrue(VideoDocument.canOpen(url: URL(fileURLWithPath: "/test.m4v")))
        XCTAssertFalse(VideoDocument.canOpen(url: URL(fileURLWithPath: "/test.mkv")))
        XCTAssertFalse(VideoDocument.canOpen(url: URL(fileURLWithPath: "/test.avi")))
        XCTAssertFalse(VideoDocument.canOpen(url: URL(fileURLWithPath: "/test.webm")))
    }
}

final class VideoEngineExportLifecycleTests: XCTestCase {

    // MARK: - Export lifecycle integration

    @MainActor
    func testExportLifecycle_successWithFixture() async throws {
        let fixtureURL = try fixtureURL(named: "sample", ext: "mp4")
        let asset = AVURLAsset(url: fixtureURL)
        let duration = try await asset.load(.duration)
        let maxTrimDuration: Double = 1.0
        let minTrimDuration: Double = 0.2
        let halfDuration = CMTimeGetSeconds(duration) / 2.0
        let clampedTrimDuration = min(maxTrimDuration, max(minTrimDuration, halfDuration))
        let end = CMTime(seconds: clampedTrimDuration, preferredTimescale: 600)
        let trimRange = CMTimeRange(start: .zero, end: end)

        let outputURL = uniqueTempURL(ext: "mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let engine = VideoEngine()
        let result = try await engine.export(
            asset: asset,
            trimRange: trimRange,
            format: .mp4H264,
            quality: .passthrough,
            outputURL: outputURL
        )

        XCTAssertEqual(result.outputURL, outputURL)
        XCTAssertGreaterThan(result.duration, 0)
        XCTAssertGreaterThan(result.fileSize, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertFalse(engine.isExporting)
        XCTAssertEqual(engine.progress, 1.0)
    }

    @MainActor
    func testExportLifecycle_failRemovesOutputFile() async throws {
        let fixtureURL = try fixtureURL(named: "sample", ext: "mp4")
        let asset = AVURLAsset(url: fixtureURL)
        let outputURL = uniqueTempURL(ext: "mov")

        // Create a file and ensure export cleans it up on failure path.
        try Data("existing".utf8).write(to: outputURL)
        do {
            _ = try await VideoEngine().export(
                asset: asset,
                trimRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 1.0, preferredTimescale: 600)),
                format: .movH264,
                quality: .passthrough,
                outputURL: outputURL
            )
            XCTFail("Expected export failure with pre-existing output file")
        } catch {
            // expected
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    @MainActor
    func testExportLifecycle_cancelRemovesPartialOutput() async throws {
        let fixtureURL = try fixtureURL(named: "sample", ext: "mp4")
        let asset = AVURLAsset(url: fixtureURL)
        let outputURL = uniqueTempURL(ext: "mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let engine = VideoEngine()
        let longTrim = CMTimeRange(start: .zero, duration: try await asset.load(.duration))

        let task = Task {
            try await engine.export(
                asset: asset,
                trimRange: longTrim,
                format: .mp4H264,
                quality: .low,
                outputURL: outputURL
            )
        }

        let didStartExport = await waitForExportToStart(engine, timeoutSeconds: 3.0)
        XCTAssertTrue(didStartExport, "Expected export to start before cancellation")
        guard didStartExport else {
            task.cancel()
            _ = try? await task.value
            return
        }

        engine.cancelExport()

        do {
            _ = try await task.value
            XCTFail("Expected cancelled export")
        } catch let error as ExportError {
            if case .cancelled = error {
                // expected
            } else {
                XCTFail("Expected cancelled export error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertFalse(engine.isExporting)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }
}

// MARK: - Private helpers (fixture & temp URL)

extension VideoEngineExportLifecycleTests {
    private func fixtureURL(named name: String, ext: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            throw XCTSkip("Missing fixture: \(name).\(ext)")
        }
        return url
    }

    private func uniqueTempURL(ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoEngineTests_\(UUID().uuidString)")
            .appendingPathExtension(ext)
    }

    @MainActor
    private func waitForExportToStart(
        _ engine: VideoEngine,
        timeoutSeconds: TimeInterval
    ) async -> Bool {
        let exportStarted = expectation(description: "Export started")
        var didStartExport = false

        let pollingTask = Task { @MainActor in
            let pollingIntervalNanos: UInt64 = 10_000_000
            let timeoutDate = Date().addingTimeInterval(timeoutSeconds)

            while Date() < timeoutDate {
                if engine.isExporting {
                    didStartExport = true
                    exportStarted.fulfill()
                    return
                }

                try? await Task.sleep(nanoseconds: pollingIntervalNanos)
            }
        }

        await fulfillment(of: [exportStarted], timeout: timeoutSeconds + 0.5)
        pollingTask.cancel()
        return didStartExport
    }
}
