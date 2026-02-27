import AVFoundation
import SwiftUI

struct ExportSheet: View {
    let document: VideoDocument
    @Bindable var trimState: TrimState
    let videoEngine: VideoEngine
    var onDismiss: () -> Void

    @State private var exportResult: VideoEngine.ExportResult?
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var capabilities: ExportCapabilities?
    @State private var isLoadingCapabilities = true
    @State private var capabilityMessage: String?

    private var resolvedSelection: ResolvedExportSelection? {
        capabilities?.resolvedSelection(
            requestedFormat: trimState.exportFormat,
            requestedQuality: trimState.qualityPreset
        )
    }

    private var effectiveQuality: QualityPreset {
        resolvedSelection?.quality
            ?? VideoEngine.effectiveQuality(
                format: trimState.exportFormat,
                quality: trimState.qualityPreset,
                sourceIsHEVC: document.isHEVC
            )
    }

    private var estimatedSize: Int64 {
        VideoEngine.estimateOutputSize(
            fileSize: document.fileSize,
            videoDuration: document.duration,
            trimRange: trimState.trimRange,
            quality: effectiveQuality
        )
    }

    private var canExport: Bool {
        guard let capabilities else { return false }
        let resolved = capabilities.resolvedSelection(
            requestedFormat: trimState.exportFormat,
            requestedQuality: trimState.qualityPreset
        )
        return capabilities.isSupported(format: resolved.format, quality: resolved.quality)
    }

    private var selectionWarning: String? {
        if let capabilityMessage {
            return capabilityMessage
        }

        guard let capabilities else { return nil }
        let support = capabilities.support(for: trimState.exportFormat, quality: trimState.qualityPreset)
        return support.isSupported ? nil : support.reason
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Export Video")
                .font(.title2)
                .fontWeight(.semibold)

            GroupBox("Trim") {
                HStack {
                    Label(TimeFormatter.preciseString(from: trimState.startTime), systemImage: "arrow.right.to.line")
                    Spacer()
                    Label(TimeFormatter.preciseString(from: trimState.endTime), systemImage: "arrow.left.to.line")
                    Spacer()
                    Label(TimeFormatter.shortDuration(from: trimState.duration), systemImage: "clock")
                }
                .font(.caption)
                .monospacedDigit()
            }

            GroupBox("Format") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Format", selection: $trimState.exportFormat) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.rawValue)
                                .tag(format)
                                .disabled(isFormatDisabled(format))
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .disabled(trimState.qualityPreset.isPassthrough || isLoadingCapabilities)
                    .onChange(of: trimState.exportFormat) { _, _ in
                        enforceValidSelection()
                    }

                    if trimState.qualityPreset.isPassthrough {
                        Text("Passthrough keeps the source container (\(document.passthroughContainerFormat.containerLabel)).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GroupBox("Quality") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Quality", selection: $trimState.qualityPreset) {
                        ForEach(QualityPreset.allCases) { preset in
                            Text(preset.rawValue)
                                .tag(preset)
                                .disabled(isQualityDisabled(preset))
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .disabled(isLoadingCapabilities)
                    .onChange(of: trimState.qualityPreset) { _, _ in
                        enforceValidSelection()
                    }

                    if trimState.qualityPreset.isPassthrough {
                        Text("Passthrough: near-instant, lossless. Trim points snap to nearest keyframe.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Re-encode: precise trim points, but slower processing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if isLoadingCapabilities {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking export compatibility for this Mac...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let selectionWarning {
                Text(selectionWarning)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            GroupBox("Output") {
                HStack {
                    Text("Estimated size:")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: estimatedSize, countStyle: .file))
                        .fontWeight(.medium)
                }
            }

            Spacer()

            if videoEngine.isExporting {
                VStack(spacing: 8) {
                    ProgressView(value: videoEngine.progress)
                    HStack {
                        Text("Exporting... \(Int(videoEngine.progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") {
                            videoEngine.cancelExport()
                        }
                    }
                }
            } else if let result = exportResult {
                VStack(spacing: 8) {
                    Label("Export complete!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Size: \(ByteCountFormatter.string(fromByteCount: result.fileSize, countStyle: .file)) - \(String(format: "%.1fs", result.duration))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([result.outputURL])
                        }
                        Button("Done") {
                            onDismiss()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
            } else {
                HStack {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Export...") {
                        startExport()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canExport || isLoadingCapabilities)
                }
            }
        }
        .padding(24)
        .frame(width: 420, height: 540)
        .alert("Export Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .task(id: document.url) {
            await loadCapabilities()
        }
    }

    private func loadCapabilities() async {
        isLoadingCapabilities = true
        do {
            let resolvedCapabilities = try await videoEngine.preflightCapabilities(
                asset: document.asset,
                sourceFileType: document.sourceFileType,
                sourceIsHEVC: document.isHEVC
            )
            capabilities = resolvedCapabilities
            enforceValidSelection()

            if !resolvedCapabilities.hasAnySupportedOption {
                capabilityMessage = "No compatible export options are available for this source on this Mac."
            }
        } catch {
            capabilityMessage = error.localizedDescription
            errorMessage = "Failed to check export compatibility: \(error.localizedDescription)"
            showingError = true
        }
        isLoadingCapabilities = false
    }

    private func enforceValidSelection() {
        guard let capabilities else { return }

        let resolved = capabilities.resolvedSelection(
            requestedFormat: trimState.exportFormat,
            requestedQuality: trimState.qualityPreset
        )

        let changed = resolved.format != trimState.exportFormat || resolved.quality != trimState.qualityPreset
        trimState.exportFormat = resolved.format
        trimState.qualityPreset = resolved.quality

        if changed {
            capabilityMessage = resolved.adjustmentReason
        }
    }

    private func isQualityDisabled(_ preset: QualityPreset) -> Bool {
        guard let capabilities else { return false }
        return capabilities.supportedFormats(for: preset).isEmpty
    }

    private func isFormatDisabled(_ format: ExportFormat) -> Bool {
        guard let capabilities else { return false }
        if trimState.qualityPreset.isPassthrough {
            return format != capabilities.sourceContainerFormat
        }
        return !capabilities.isSupported(format: format, quality: trimState.qualityPreset)
    }

    private func startExport() {
        guard let capabilities else {
            errorMessage = "Export compatibility has not finished loading yet."
            showingError = true
            return
        }

        let resolved = capabilities.resolvedSelection(
            requestedFormat: trimState.exportFormat,
            requestedQuality: trimState.qualityPreset
        )
        guard capabilities.isSupported(format: resolved.format, quality: resolved.quality) else {
            errorMessage = capabilities.support(for: resolved.format, quality: resolved.quality).reason
                ?? "The selected export option is not supported on this Mac."
            showingError = true
            return
        }

        trimState.exportFormat = resolved.format
        trimState.qualityPreset = resolved.quality

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [resolved.format.contentType]
        savePanel.nameFieldStringValue = exportFileName(for: resolved.format)
        savePanel.canCreateDirectories = true

        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        Task {
            do {
                let result = try await videoEngine.export(
                    asset: document.asset,
                    trimRange: trimState.trimRange,
                    format: resolved.format,
                    quality: resolved.quality,
                    outputURL: url,
                    sourceIsHEVC: document.isHEVC,
                    sourceURL: document.url,
                    sourceFileType: document.sourceFileType
                )
                exportResult = result
            } catch is CancellationError {
                // User cancelled, do nothing
            } catch ExportError.cancelled {
                // Export cancelled
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func exportFileName(for format: ExportFormat) -> String {
        let baseName = document.url.deletingPathExtension().lastPathComponent
        return "\(baseName)_trimmed.\(format.fileExtension)"
    }
}
