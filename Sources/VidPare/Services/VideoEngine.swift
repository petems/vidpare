import AVFoundation

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

    func export(
        asset: AVURLAsset,
        trimRange: CMTimeRange,
        format: ExportFormat,
        quality: QualityPreset,
        outputURL: URL
    ) async throws -> ExportResult {
        // If HEVC is selected with passthrough, auto-promote to high quality re-encode
        let effectiveQuality = (format.isHEVC && quality.isPassthrough) ? .high : quality

        let preset = effectiveQuality.exportPreset

        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ExportError.sessionCreationFailed
        }

        session.outputURL = outputURL
        session.outputFileType = format.fileType
        session.timeRange = trimRange

        self.exportSession = session
        self.isExporting = true
        self.progress = 0

        startProgressPolling(session: session)

        let startDate = Date()

        do {
            await session.export()

            stopProgressPolling()

            guard session.status == .completed else {
                self.isExporting = false
                try? FileManager.default.removeItem(at: outputURL)
                if session.status == .cancelled {
                    throw ExportError.cancelled
                }
                throw ExportError.exportFailed(session.error?.localizedDescription ?? "Unknown error")
            }

            let elapsed = Date().timeIntervalSince(startDate)
            let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
            let fileSize = (attrs?[.size] as? Int64) ?? 0

            self.isExporting = false
            self.progress = 1.0

            return ExportResult(outputURL: outputURL, duration: elapsed, fileSize: fileSize)
        } catch {
            stopProgressPolling()
            self.isExporting = false
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    func cancelExport() {
        exportSession?.cancelExport()
        stopProgressPolling()
        isExporting = false
    }

    /// Estimate output file size in bytes
    static func estimateOutputSize(
        fileSize: Int64,
        videoDuration: CMTime,
        trimRange: CMTimeRange,
        quality: QualityPreset
    ) -> Int64 {
        let totalSeconds = CMTimeGetSeconds(videoDuration)
        let trimSeconds = CMTimeGetSeconds(trimRange.duration)
        guard totalSeconds > 0 else { return 0 }

        let ratio = trimSeconds / totalSeconds

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

    // MARK: - Private

    private func startProgressPolling(session: AVAssetExportSession) {
        DispatchQueue.main.async { [weak self] in
            self?.progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                let newProgress = Double(session.progress)
                if newProgress >= (self?.progress ?? 0) {
                    self?.progress = newProgress
                }
            }
        }
    }

    private func stopProgressPolling() {
        DispatchQueue.main.async { [weak self] in
            self?.progressTimer?.invalidate()
            self?.progressTimer = nil
        }
    }
}

enum ExportError: LocalizedError {
    case sessionCreationFailed
    case exportFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .sessionCreationFailed:
            return "Failed to create export session. The file format may not support the selected export settings."
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .cancelled:
            return "Export was cancelled."
        }
    }
}
