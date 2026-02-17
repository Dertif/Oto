import Foundation

enum TranscriptArtifactKind: String, Equatable {
    case transcript
    case raw
    case refined

    var title: String {
        switch self {
        case .transcript:
            return "Transcript"
        case .raw:
            return "Raw"
        case .refined:
            return "Refined"
        }
    }
}

struct TranscriptHistoryEntry: Identifiable, Equatable {
    let id: String
    let url: URL
    let kind: TranscriptArtifactKind
    let isEnhanced: Bool
    let timestamp: Date
    let backendLabel: String
    let textBody: String
    let lineCount: Int
}
