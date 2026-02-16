import Foundation

struct TranscriptArtifacts: Equatable {
    var primaryURL: URL?
    var failureContextURL: URL?

    static let empty = TranscriptArtifacts(primaryURL: nil, failureContextURL: nil)
}
