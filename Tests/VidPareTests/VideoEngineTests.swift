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

    // MARK: - ExportCapabilities

    func testCapabilitiesResolve_hevcPassthroughPromotesToReencodeWhenSourceIsNotHEVC() {
        let capabilities = ExportCapabilities(
            sourceContainerFormat: .mp4H264,
            sourceIsHEVC: false,
            supportMatrix: supportMatrix(
                overrides: [
                    SupportOverride(quality: .passthrough, format: .mp4H264, support: .supported),
                    SupportOverride(quality: .high, format: .mp4H264, support: .supported),
                    SupportOverride(quality: .high, format: .mp4HEVC, support: .supported)
                ]
            )
        )

        let resolved = capabilities.resolvedSelection(
            requestedFormat: .mp4HEVC,
            requestedQuality: .passthrough
        )

        XCTAssertEqual(resolved.format, .mp4HEVC)
        XCTAssertEqual(resolved.quality, .high)
        XCTAssertNotNil(resolved.adjustmentReason)
    }

    func testCapabilitiesResolve_fallsBackToSupportedFormatAtRequestedQuality() {
        let capabilities = ExportCapabilities(
            sourceContainerFormat: .mp4H264,
            sourceIsHEVC: true,
            supportMatrix: supportMatrix(
                overrides: [
                    SupportOverride(quality: .high, format: .mp4H264, support: .supported),
                    SupportOverride(quality: .high, format: .movH264, support: .supported)
                ]
            )
        )

        let resolved = capabilities.resolvedSelection(
            requestedFormat: .mp4HEVC,
            requestedQuality: .high
        )

        XCTAssertEqual(resolved.quality, .high)
        XCTAssertEqual(resolved.format, .mp4H264)
    }

    func testCapabilitiesResolve_fallsBackToFirstSupportedQualityWhenRequestedQualityUnavailable() {
        let capabilities = ExportCapabilities(
            sourceContainerFormat: .movH264,
            sourceIsHEVC: false,
            supportMatrix: supportMatrix(
                overrides: [
                    SupportOverride(quality: .medium, format: .movH264, support: .supported)
                ]
            )
        )

        let resolved = capabilities.resolvedSelection(
            requestedFormat: .mp4HEVC,
            requestedQuality: .high
        )

        XCTAssertEqual(resolved.quality, .medium)
        XCTAssertEqual(resolved.format, .movH264)
    }

    func testCapabilitiesSupportedFormats_filtersUnsupportedOptions() {
        let capabilities = ExportCapabilities(
            sourceContainerFormat: .mp4H264,
            sourceIsHEVC: false,
            supportMatrix: supportMatrix(
                overrides: [
                    SupportOverride(quality: .high, format: .mp4H264, support: .supported),
                    SupportOverride(quality: .high, format: .movH264, support: .supported)
                ]
            )
        )

        XCTAssertEqual(capabilities.supportedFormats(for: .high), [.mp4H264, .movH264])
        XCTAssertTrue(capabilities.supportedFormats(for: .passthrough).isEmpty)
    }

    // MARK: - Capability preflight

    func testBuildCapabilities_passthroughOnlySupportsSourceContainer() {
        let asset = AVURLAsset(url: URL(fileURLWithPath: "/tmp/nonexistent.mp4"))
        let capabilities = VideoEngine.buildCapabilities(
            asset: asset,
            sourceFileType: .mov,
            sourceIsHEVC: false
        )

        XCTAssertEqual(capabilities.sourceContainerFormat, .movH264)
        XCTAssertFalse(capabilities.support(for: .mp4H264, quality: .passthrough).isSupported)
    }
}

private struct SupportOverride {
    let quality: QualityPreset
    let format: ExportFormat
    let support: ExportSupport
}

private func supportMatrix(
    overrides: [SupportOverride]
) -> [QualityPreset: [ExportFormat: ExportSupport]] {
    var matrix: [QualityPreset: [ExportFormat: ExportSupport]] = [:]
    for quality in QualityPreset.allCases {
        var row: [ExportFormat: ExportSupport] = [:]
        for format in ExportFormat.allCases {
            row[format] = .unsupported("Unsupported")
        }
        matrix[quality] = row
    }

    for override in overrides {
        matrix[override.quality]?[override.format] = override.support
    }

    return matrix
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

        // Use a non-existent parent directory so the export session cannot
        // write its temp file, causing a genuine export failure.
        let nonExistentDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vidpare-nonexistent-\(UUID().uuidString)")
        let outputURL = nonExistentDir.appendingPathComponent("output.mp4")

        let engine = VideoEngine()
        do {
            _ = try await engine.export(
                asset: asset,
                trimRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 1.0, preferredTimescale: 600)),
                format: .mp4H264,
                quality: .low,
                outputURL: outputURL
            )
            XCTFail("Expected export failure with non-writable output path")
        } catch {
            // expected
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertFalse(engine.isExporting, "isExporting should be reset after failure")
        XCTAssertEqual(engine.progress, 0, "progress should be reset after failure")
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

        XCTAssertFalse(engine.isExporting, "isExporting should be reset after cancel")
        XCTAssertEqual(engine.progress, 0, "progress should be reset after cancel")
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
