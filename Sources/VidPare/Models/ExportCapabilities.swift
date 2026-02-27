import Foundation

struct ExportSupport: Equatable {
    let isSupported: Bool
    let reason: String?

    static let supported = ExportSupport(isSupported: true, reason: nil)

    static func unsupported(_ reason: String) -> ExportSupport {
        ExportSupport(isSupported: false, reason: reason)
    }
}

struct ResolvedExportSelection: Equatable {
    let format: ExportFormat
    let quality: QualityPreset
    let adjustmentReason: String?
}

struct ExportCapabilities {
    let sourceContainerFormat: ExportFormat
    let sourceIsHEVC: Bool

    private let supportMatrix: [QualityPreset: [ExportFormat: ExportSupport]]

    init(
        sourceContainerFormat: ExportFormat,
        sourceIsHEVC: Bool,
        supportMatrix: [QualityPreset: [ExportFormat: ExportSupport]]
    ) {
        self.sourceContainerFormat = sourceContainerFormat
        self.sourceIsHEVC = sourceIsHEVC
        self.supportMatrix = supportMatrix
    }

    func support(for format: ExportFormat, quality: QualityPreset) -> ExportSupport {
        supportMatrix[quality]?[format] ?? .unsupported("This export option is not available on this Mac.")
    }

    func isSupported(format: ExportFormat, quality: QualityPreset) -> Bool {
        support(for: format, quality: quality).isSupported
    }

    func supportedFormats(for quality: QualityPreset) -> [ExportFormat] {
        ExportFormat.allCases.filter { support(for: $0, quality: quality).isSupported }
    }

    var supportedQualities: [QualityPreset] {
        QualityPreset.allCases.filter { !supportedFormats(for: $0).isEmpty }
    }

    var hasAnySupportedOption: Bool {
        !supportedQualities.isEmpty
    }

    func resolvedSelection(
        requestedFormat: ExportFormat,
        requestedQuality: QualityPreset
    ) -> ResolvedExportSelection {
        if isSupported(format: requestedFormat, quality: requestedQuality) {
            return ResolvedExportSelection(
                format: requestedFormat,
                quality: requestedQuality,
                adjustmentReason: nil
            )
        }

        if requestedQuality.isPassthrough && requestedFormat.isHEVC && !sourceIsHEVC {
            let hevcFallbackQualities: [QualityPreset] = [.high, .medium, .low]
            if let fallbackQuality = hevcFallbackQualities.first(where: {
                isSupported(format: requestedFormat, quality: $0)
            }) {
                return ResolvedExportSelection(
                    format: requestedFormat,
                    quality: fallbackQuality,
                    adjustmentReason: "HEVC passthrough requires an HEVC source; switched to re-encode."
                )
            }
        }

        if let fallbackFormat = supportedFormats(for: requestedQuality).first {
            return ResolvedExportSelection(
                format: fallbackFormat,
                quality: requestedQuality,
                adjustmentReason: support(for: requestedFormat, quality: requestedQuality).reason
            )
        }

        if let fallbackQuality = supportedQualities.first,
           let fallbackFormat = supportedFormats(for: fallbackQuality).first {
            return ResolvedExportSelection(
                format: fallbackFormat,
                quality: fallbackQuality,
                adjustmentReason: support(for: requestedFormat, quality: requestedQuality).reason
            )
        }

        return ResolvedExportSelection(
            format: requestedFormat,
            quality: requestedQuality,
            adjustmentReason: support(for: requestedFormat, quality: requestedQuality).reason
        )
    }
}
