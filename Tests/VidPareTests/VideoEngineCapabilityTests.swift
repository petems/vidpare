import AVFoundation
@testable import VidPare
import XCTest

final class VideoEngineCapabilityTests: XCTestCase {

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

    func testCapabilitiesResolve_gifPassthroughPromotesToReencode() {
        let capabilities = ExportCapabilities(
            sourceContainerFormat: .mp4H264,
            sourceIsHEVC: false,
            supportMatrix: supportMatrix(
                overrides: [
                    SupportOverride(quality: .high, format: .gif, support: .supported),
                    SupportOverride(quality: .passthrough, format: .mp4H264, support: .supported)
                ]
            )
        )

        let resolved = capabilities.resolvedSelection(
            requestedFormat: .gif,
            requestedQuality: .passthrough
        )

        XCTAssertEqual(resolved.format, .gif)
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

    // MARK: - Export filename generation

    func testExportFileNameGeneration() {
        let paths = ["/tmp/MyVideo.mp4", "/tmp/recording.mov", "/tmp/My Holiday Video.mp4", "/tmp/clip.m4v", "/tmp/screen-capture.mov"]
        let formats: [ExportFormat] = [.mp4H264, .movH264, .mp4H264, .mp4HEVC, .gif]
        let expected = ["MyVideo_trimmed.mp4", "recording_trimmed.mov", "My Holiday Video_trimmed.mp4", "clip_trimmed.mp4", "screen-capture_trimmed.gif"]

        for i in paths.indices {
            let url = URL(fileURLWithPath: paths[i])
            let name = ExportSheet.exportFileName(sourceURL: url, format: formats[i])
            XCTAssertEqual(name, expected[i], "Failed for input: '\(paths[i])'")
        }
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
        XCTAssertFalse(capabilities.support(for: .gif, quality: .passthrough).isSupported)
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
