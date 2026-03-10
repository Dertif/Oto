import Foundation

enum WhisperCppModelDownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case failed(String)

    var progressValue: Double? {
        guard case let .downloading(progress) = self else {
            return nil
        }
        return progress
    }

    var label: String {
        switch self {
        case .notDownloaded:
            return "Not downloaded"
        case let .downloading(progress):
            return "Downloading \(Int(progress * 100))%"
        case .downloaded:
            return "Downloaded"
        case let .failed(message):
            return "Failed: \(message)"
        }
    }
}

struct WhisperCppRuntimeSnapshot: Equatable {
    let selectedModel: WhisperCppModel
    let modelStatusLabel: String
    let runtimeStatusLabel: String
    let downloadState: WhisperCppModelDownloadState
}
