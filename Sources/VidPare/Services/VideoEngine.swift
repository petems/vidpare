import AVFoundation
import Observation

@MainActor
@Observable
final class VideoEngine {
    private(set) var isExporting = false
    private(set) var progress: Double = 0
    private var exportSession: AVAssetExportSession?
    private var progressTimer: Timer?

    struct ExportResult {
        let outputURL: URL
        let duration: TimeInterval
        let fileSize: Int64
    }

    nonisolated static func effectiveQuality(
        format: ExportFormat,
        quality: QualityPreset,
        sourceIsHEVC: Bool
    ) -> QualityPreset {
        (format.isHEVC && quality.isPassthrough && !sourceIsHEVC) ? .high : quality
    }

    func preflightCapabilities(
        asset: AVURLAsset,
        sourceFileType: AVFileType? = nil,
        sourceIsHEVC: Bool = false
    ) async throws -> ExportCapabilities {
        Self.buildCapabilities(
            asset: asset,
            sourceFileType: sourceFileType,
            sourceIsHEVC: sourceIsHEVC
        )
    }

    func export(
        asset: AVURLAsset,
        trimRange: CMTimeRange,
        format: ExportFormat,
        quality: QualityPreset,
        outputURL: URL,
        sourceIsHEVC: Bool = false,
        sourceURL: URL? = nil,
        sourceFileType: AVFileType? = nil
    ) async throws -> ExportResult {
        let (requestedFormat, requestedQuality) = try await resolveRequestedSelection(
            asset: asset,
            format: format,
            quality: quality,
            sourceFileType: sourceFileType,
            sourceIsHEVC: sourceIsHEVC
        )

        let scopedAccess = sourceURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if scopedAccess, let sourceURL {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let tempOutputURL = temporaryOutputURL(for: outputURL)
        let session = try createExportSession(
            asset: asset,
            requestedQuality: requestedQuality,
            requestedFormat: requestedFormat,
            trimRange: trimRange,
            tempOutputURL: tempOutputURL
        )
        startProgressPolling()

        let startDate = Date()
        let destinationExistedBeforeExport = FileManager.default.fileExists(atPath: outputURL.path)

        do {
            await session.export()
            stopProgressPolling()

            return try finalizeExportResult(
                session: session,
                tempOutputURL: tempOutputURL,
                outputURL: outputURL,
                destinationExistedBeforeExport: destinationExistedBeforeExport,
                startDate: startDate
            )
        } catch {
            stopProgressPolling()
            self.isExporting = false
            try? FileManager.default.removeItem(at: tempOutputURL)
            throw error
        }
    }

    func cancelExport() {
        exportSession?.cancelExport()
        stopProgressPolling()
        isExporting = false
    }

    /// Estimate output file size in bytes
    nonisolated static func estimateOutputSize(
        fileSize: Int64,
        videoDuration: CMTime,
        trimRange: CMTimeRange,
        quality: QualityPreset
    ) -> Int64 {
        let totalSeconds = CMTimeGetSeconds(videoDuration)
        let trimSeconds = CMTimeGetSeconds(trimRange.duration)
        guard totalSeconds > 0, totalSeconds.isFinite else { return 0 }

        let rawRatio = trimSeconds / totalSeconds
        guard rawRatio.isFinite else { return 0 }
        let ratio = min(max(rawRatio, 0.0), 1.0)

        switch quality {
        case .passthrough:
            return Int64(Double(fileSize) * ratio)
        case .high:
            return Int64(Double(fileSize) * ratio * 0.9)
        case .medium:
            return Int64(Double(fileSize) * ratio * 0.5)
        case .low:
            return Int64(Double(fileSize) * ratio * 0.25)
        }
    }

    nonisolated static func isHEVCEncodeSupported() -> Bool {
        AVAssetExportSession.allExportPresets().contains(AVAssetExportPresetHEVCHighestQuality)
    }

    nonisolated static func buildCapabilities(
        asset: AVURLAsset,
        sourceFileType: AVFileType? = nil,
        sourceIsHEVC: Bool = false
    ) -> ExportCapabilities {
        let sourceContainer = ExportFormat.passthroughContainerFormat(
            sourceFileType: sourceFileType,
            sourceIsHEVC: sourceIsHEVC
        )
        let hevcSupported = isHEVCEncodeSupported()

        var matrix: [QualityPreset: [ExportFormat: ExportSupport]] = [:]

        for quality in QualityPreset.allCases {
            var row: [ExportFormat: ExportSupport] = [:]
            let preset = quality.exportPreset

            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
                for format in ExportFormat.allCases {
                    row[format] = .unsupported("The \(quality.rawValue) preset is not compatible with this source.")
                }
                matrix[quality] = row
                continue
            }

            let supportedFileTypes = Set(session.supportedFileTypes)

            for format in ExportFormat.allCases {
                if quality.isPassthrough {
                    if format != sourceContainer {
                        row[format] = .unsupported("Passthrough keeps the source container (\(sourceContainer.containerLabel)).")
                    } else if supportedFileTypes.contains(sourceContainer.fileType) {
                        row[format] = .supported
                    } else {
                        row[format] = .unsupported("Passthrough is unavailable for this source container on this Mac.")
                    }
                    continue
                }

                guard supportedFileTypes.contains(format.fileType) else {
                    row[format] = .unsupported("The \(format.containerLabel) container is not available with \(quality.rawValue) on this Mac.")
                    continue
                }

                if format.isHEVC && !hevcSupported {
                    row[format] = .unsupported("HEVC export is not supported on this Mac.")
                    continue
                }

                row[format] = .supported
            }

            matrix[quality] = row
        }

        return ExportCapabilities(
            sourceContainerFormat: sourceContainer,
            sourceIsHEVC: sourceIsHEVC,
            supportMatrix: matrix
        )
    }

    nonisolated static func shouldRemoveOutputOnFailure(outputExistedBeforeExport: Bool) -> Bool {
        !outputExistedBeforeExport
    }

    // MARK: - Private

    private func resolveRequestedSelection(
        asset: AVURLAsset,
        format: ExportFormat,
        quality: QualityPreset,
        sourceFileType: AVFileType?,
        sourceIsHEVC: Bool
    ) async throws -> (ExportFormat, QualityPreset) {
        let capabilities = try await preflightCapabilities(
            asset: asset,
            sourceFileType: sourceFileType,
            sourceIsHEVC: sourceIsHEVC
        )

        let requestedQuality = Self.effectiveQuality(
            format: format,
            quality: quality,
            sourceIsHEVC: sourceIsHEVC
        )
        let requestedFormat = requestedQuality.isPassthrough ? capabilities.sourceContainerFormat : format

        guard capabilities.isSupported(format: requestedFormat, quality: requestedQuality) else {
            let reason = capabilities.support(for: requestedFormat, quality: requestedQuality).reason
                ?? "This export option is not available on this Mac."
            throw ExportError.incompatibleSelection(reason)
        }

        return (requestedFormat, requestedQuality)
    }

    private func createExportSession(
        asset: AVURLAsset,
        requestedQuality: QualityPreset,
        requestedFormat: ExportFormat,
        trimRange: CMTimeRange,
        tempOutputURL: URL
    ) throws -> AVAssetExportSession {
        guard let session = AVAssetExportSession(asset: asset, presetName: requestedQuality.exportPreset) else {
            throw ExportError.sessionCreationFailed
        }

        session.outputURL = tempOutputURL
        session.outputFileType = requestedFormat.fileType
        session.timeRange = trimRange

        self.exportSession = session
        self.isExporting = true
        self.progress = 0

        return session
    }

    private func finalizeExportResult(
        session: AVAssetExportSession,
        tempOutputURL: URL,
        outputURL: URL,
        destinationExistedBeforeExport: Bool,
        startDate: Date
    ) throws -> ExportResult {
        guard session.status == .completed else {
            self.isExporting = false
            try? FileManager.default.removeItem(at: tempOutputURL)
            if session.status == .cancelled {
                throw ExportError.cancelled
            }
            throw ExportError.exportFailed(session.error?.localizedDescription ?? "Unknown error")
        }

        let finalizedURL = try finalizeExportedFile(
            from: tempOutputURL,
            to: outputURL,
            destinationExistedBeforeExport: destinationExistedBeforeExport
        )

        let elapsed = Date().timeIntervalSince(startDate)
        let attrs = try? FileManager.default.attributesOfItem(atPath: finalizedURL.path)
        let fileSize = (attrs?[.size] as? Int64) ?? 0

        self.isExporting = false
        self.progress = 1.0

        return ExportResult(outputURL: finalizedURL, duration: elapsed, fileSize: fileSize)
    }

    private func startProgressPolling() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let session = self?.exportSession else { return }
                let newProgress = Double(session.progress)
                if newProgress >= (self?.progress ?? 0) {
                    self?.progress = newProgress
                }
            }
        }
    }

    private func stopProgressPolling() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func temporaryOutputURL(for finalURL: URL) -> URL {
        let filename = ".vidpare-\(UUID().uuidString)-\(finalURL.lastPathComponent)"
        return finalURL.deletingLastPathComponent().appendingPathComponent(filename)
    }

    private func finalizeExportedFile(
        from temporaryURL: URL,
        to outputURL: URL,
        destinationExistedBeforeExport: Bool
    ) throws -> URL {
        if destinationExistedBeforeExport {
            let resultingURL = try FileManager.default.replaceItemAt(
                outputURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
            return resultingURL ?? outputURL
        }

        try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        return outputURL
    }
}

enum ExportError: LocalizedError {
    case sessionCreationFailed
    case incompatibleSelection(String)
    case exportFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .sessionCreationFailed:
            return "Failed to create export session. The file format may not support the selected export settings."
        case .incompatibleSelection(let reason):
            return "The selected export options are incompatible: \(reason)"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .cancelled:
            return "Export was cancelled."
        }
    }
}
