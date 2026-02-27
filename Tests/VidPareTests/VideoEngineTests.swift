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

}
