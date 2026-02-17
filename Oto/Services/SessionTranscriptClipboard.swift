import Foundation

@MainActor
final class SessionTranscriptClipboard {
    private(set) var latestTranscript: String?
    private(set) var updatedAt: Date?

    func update(with transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        latestTranscript = trimmed
        updatedAt = Date()
    }

    func clear() {
        latestTranscript = nil
        updatedAt = nil
    }
}
