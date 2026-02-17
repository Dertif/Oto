import Foundation

struct TranscriptArtifacts: Equatable {
    var primaryURL: URL?
    var rawURL: URL?
    var refinedURL: URL?
    var failureContextURL: URL?

    static let empty = TranscriptArtifacts(primaryURL: nil, rawURL: nil, refinedURL: nil, failureContextURL: nil)
}
