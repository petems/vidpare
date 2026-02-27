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

    private var estimatedSize: Int64 {
        VideoEngine.estimateOutputSize(
            fileSize: document.fileSize,
            videoDuration: document.duration,
            trimRange: trimState.trimRange,
            quality: effectiveQuality
        )
    }

    private var effectiveQuality: QualityPreset {
        VideoEngine.effectiveQuality(
            format: trimState.exportFormat,
            quality: trimState.qualityPreset,
            sourceIsHEVC: document.isHEVC
        )
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Export Video")
                .font(.title2)
                .fontWeight(.semibold)

            // Trim summary
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

            // Format picker
            GroupBox("Format") {
                Picker("Format", selection: $trimState.exportFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.radioGroup)
                .disabled(trimState.qualityPreset.isPassthrough)
            }

            // Quality picker
            GroupBox("Quality") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Quality", selection: $trimState.qualityPreset) {
                        ForEach(QualityPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                                .disabled(preset.isPassthrough && trimState.exportFormat.isHEVC && !document.isHEVC)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: trimState.exportFormat) { _, newValue in
                        if newValue.isHEVC && trimState.qualityPreset.isPassthrough && !document.isHEVC {
                            trimState.qualityPreset = .high
                        }
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

            // Estimated size
            GroupBox("Output") {
                HStack {
                    Text("Estimated size:")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: estimatedSize, countStyle: .file))
                        .fontWeight(.medium)
                }
            }

            Spacer()

            // Export progress or buttons
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
                    Text("Size: \(ByteCountFormatter.string(fromByteCount: result.fileSize, countStyle: .file)) — \(String(format: "%.1fs", result.duration))")
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
                }
            }
        }
        .padding(24)
        .frame(width: 400, height: 500)
        .alert("Export Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    private func startExport() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [trimState.exportFormat.contentType]
        savePanel.nameFieldStringValue = exportFileName()
        savePanel.canCreateDirectories = true

        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        Task {
            do {
                let result = try await videoEngine.export(
                    asset: document.asset,
                    trimRange: trimState.trimRange,
                    format: trimState.exportFormat,
                    quality: effectiveQuality,
                    outputURL: url,
                    sourceIsHEVC: document.isHEVC,
                    sourceURL: document.url
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

    private func exportFileName() -> String {
        let baseName = document.url.deletingPathExtension().lastPathComponent
        return "\(baseName)_trimmed.\(trimState.exportFormat.fileExtension)"
    }
}
