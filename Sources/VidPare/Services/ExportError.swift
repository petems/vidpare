import Foundation

enum ExportError: LocalizedError {
    case sessionCreationFailed
    case incompatibleSelection(String)
    case exportFailed(String)
    case gifDurationLimitExceeded(maxSeconds: TimeInterval)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .sessionCreationFailed:
            return "Failed to create export session. The file format may not support the selected export settings."
        case .incompatibleSelection(let reason):
            return "The selected export options are incompatible: \(reason)"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .gifDurationLimitExceeded(let maxSeconds):
            return "GIF export is limited to \(Int(maxSeconds)) seconds. Reduce the trim range and try again."
        case .cancelled:
            return "Export was cancelled."
        }
    }
}
