import AVFoundation
import Observation

@MainActor
@Observable
final class VideoEngine: @unchecked Sendable {
    private(set) var isExporting = false
    private(set) var progress: Double = 0
    private var exportSession: AVAssetExportSession?
    private var gifExportTask: Task<Void, Error>?
    private var exportGeneration: UInt64 = 0
    private var progressTimer: Timer?

    struct ExportResult {
        let outputURL: URL
        let duration: TimeInterval
        let fileSize: Int64
    }

    private struct FinalizeContext {
        let outputURL: URL
        let destinationExistedBeforeExport: Bool
        let startDate: Date
        let generation: UInt64
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
        sourceFileType: AVFileType? = nil,
        gifSettings: GIFExportSettings = GIFExportSettings()
    ) async throws -> ExportResult {
        let generation = beginExportGeneration()
        let scopedAccess = sourceURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if scopedAccess, let sourceURL {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let (requestedFormat, requestedQuality) = try await resolveRequestedSelection(
            asset: asset,
            format: format,
            quality: quality,
            sourceFileType: sourceFileType,
            sourceIsHEVC: sourceIsHEVC
        )

        if requestedFormat == .gif {
            return try await exportGIF(
                asset: asset,
                trimRange: trimRange,
                outputURL: outputURL,
                gifSettings: gifSettings,
                generation: generation
            )
        }

        let tempOutputURL = temporaryOutputURL(for: outputURL)
        let session = try createExportSession(
            asset: asset,
            requestedQuality: requestedQuality,
            requestedFormat: requestedFormat,
            trimRange: trimRange,
            tempOutputURL: tempOutputURL
        )
        startProgressPolling(generation: generation)

        let startDate = Date()
        let destinationExistedBeforeExport = FileManager.default.fileExists(atPath: outputURL.path)

        do {
            await session.export()
            stopProgressPolling()

            let finalizeContext = FinalizeContext(
                outputURL: outputURL,
                destinationExistedBeforeExport: destinationExistedBeforeExport,
                startDate: startDate,
                generation: generation
            )

            return try finalizeExportResult(
                session: session,
                tempOutputURL: tempOutputURL,
                context: finalizeContext
            )
        } catch {
            resetExportStateIfCurrent(generation: generation)
            if isCurrentGeneration(generation) {
                try? FileManager.default.removeItem(at: tempOutputURL)
            }
            throw error
        }
    }

    func cancelExport() {
        _ = beginExportGeneration()
        exportSession?.cancelExport()
        gifExportTask?.cancel()
        gifExportTask = nil
        resetExportState()
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
                    if format == .gif {
                        row[format] = quality.isPassthrough
                            ? .unsupported("GIF export requires re-encoding; passthrough is unavailable.")
                            : .supported
                    } else {
                        row[format] = .unsupported("The \(quality.rawValue) preset is not compatible with this source.")
                    }
                }
                matrix[quality] = row
                continue
            }

            let supportedFileTypes = Set(session.supportedFileTypes)

            for format in ExportFormat.allCases {
                if format == .gif {
                    if quality.isPassthrough {
                        row[format] = .unsupported("GIF export requires re-encoding; passthrough is unavailable.")
                    } else {
                        row[format] = .supported
                    }
                    continue
                }

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

    // MARK: - Private

    private func beginExportGeneration() -> UInt64 {
        exportGeneration &+= 1
        return exportGeneration
    }

    private func isCurrentGeneration(_ generation: UInt64) -> Bool {
        exportGeneration == generation
    }

    private func resetExportStateIfCurrent(generation: UInt64) {
        guard isCurrentGeneration(generation) else { return }
        resetExportState()
    }

    private func resetExportState() {
        stopProgressPolling()
        exportSession = nil
        isExporting = false
        progress = 0
    }

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

        let resolved = capabilities.resolvedSelection(
            requestedFormat: format,
            requestedQuality: requestedQuality
        )

        guard capabilities.isSupported(format: resolved.format, quality: resolved.quality) else {
            let reason = capabilities.support(for: resolved.format, quality: resolved.quality).reason
                ?? "This export option is not available on this Mac."
            throw ExportError.incompatibleSelection(reason)
        }

        return (resolved.format, resolved.quality)
    }

    private func createExportSession(
        asset: AVURLAsset,
        requestedQuality: QualityPreset,
        requestedFormat: ExportFormat,
        trimRange: CMTimeRange,
        tempOutputURL: URL
    ) throws -> AVAssetExportSession {
        guard requestedFormat != .gif else {
            throw ExportError.sessionCreationFailed
        }

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
        context: FinalizeContext
    ) throws -> ExportResult {
        guard isCurrentGeneration(context.generation) else {
            throw ExportError.cancelled
        }

        guard session.status == .completed else {
            resetExportStateIfCurrent(generation: context.generation)
            try? FileManager.default.removeItem(at: tempOutputURL)
            if session.status == .cancelled {
                throw ExportError.cancelled
            }
            throw ExportError.exportFailed(session.error?.localizedDescription ?? "Unknown error")
        }

        return try finalizeExportedTemporaryResult(
            tempOutputURL: tempOutputURL,
            context: context
        )
    }

    private func finalizeExportedTemporaryResult(
        tempOutputURL: URL,
        context: FinalizeContext
    ) throws -> ExportResult {
        guard isCurrentGeneration(context.generation) else {
            throw ExportError.cancelled
        }

        let finalizedURL = try finalizeExportedFile(
            from: tempOutputURL,
            to: context.outputURL,
            destinationExistedBeforeExport: context.destinationExistedBeforeExport
        )

        let elapsed = Date().timeIntervalSince(context.startDate)
        let attrs = try? FileManager.default.attributesOfItem(atPath: finalizedURL.path)
        let fileSize = (attrs?[.size] as? Int64) ?? 0

        self.isExporting = false
        self.progress = 1.0

        return ExportResult(outputURL: finalizedURL, duration: elapsed, fileSize: fileSize)
    }

    private func startProgressPolling(generation: UInt64) {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard self?.isCurrentGeneration(generation) == true else { return }
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

private extension VideoEngine {
    func exportGIF(
        asset: AVURLAsset,
        trimRange: CMTimeRange,
        outputURL: URL,
        gifSettings: GIFExportSettings,
        generation: UInt64
    ) async throws -> ExportResult {
        let trimSeconds = CMTimeGetSeconds(trimRange.duration)
        guard trimSeconds > 0, trimSeconds.isFinite else {
            throw ExportError.incompatibleSelection("Select a non-zero trim range to export GIF.")
        }

        if trimSeconds > GIFExportSettings.maxDurationSeconds {
            throw ExportError.gifDurationLimitExceeded(maxSeconds: GIFExportSettings.maxDurationSeconds)
        }

        let tempOutputURL = temporaryOutputURL(for: outputURL)
        let destinationExistedBeforeExport = FileManager.default.fileExists(atPath: outputURL.path)
        let startDate = Date()

        isExporting = true
        progress = 0

        let task = Task.detached(priority: .userInitiated) { [asset, trimRange, tempOutputURL, gifSettings, generation] in
            try await Self.renderGIF(
                asset: asset,
                trimRange: trimRange,
                outputURL: tempOutputURL,
                settings: gifSettings
            ) { [engine = self] updatedProgress in
                await MainActor.run {
                    guard engine.isCurrentGeneration(generation), engine.isExporting else { return }
                    if updatedProgress >= engine.progress {
                        engine.progress = updatedProgress
                    }
                }
            }
        }

        gifExportTask = task

        do {
            try await task.value
            gifExportTask = nil
            guard isCurrentGeneration(generation) else {
                throw ExportError.cancelled
            }
            let finalizeContext = FinalizeContext(
                outputURL: outputURL,
                destinationExistedBeforeExport: destinationExistedBeforeExport,
                startDate: startDate,
                generation: generation
            )
            return try finalizeExportedTemporaryResult(
                tempOutputURL: tempOutputURL,
                context: finalizeContext
            )
        } catch is CancellationError {
            gifExportTask = nil
            resetExportStateIfCurrent(generation: generation)
            if isCurrentGeneration(generation) {
                try? FileManager.default.removeItem(at: tempOutputURL)
            }
            throw ExportError.cancelled
        } catch {
            gifExportTask = nil
            resetExportStateIfCurrent(generation: generation)
            if isCurrentGeneration(generation) {
                try? FileManager.default.removeItem(at: tempOutputURL)
            }
            throw error
        }
    }
}
