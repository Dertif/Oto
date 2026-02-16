import Foundation

final class TranscriptStore {
    let folderURL: URL
    private let fileManager: FileManager
    private let nowProvider: () -> Date

    init(
        folderURL: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/Oto/Transcripts", isDirectory: true),
        fileManager: FileManager = .default,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.folderURL = folderURL
        self.fileManager = fileManager
        self.nowProvider = nowProvider
    }

    func save(text: String, backend: STTBackend, prefix: String) throws -> URL {
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let now = nowProvider()
        let timestamp = formatter.string(from: now)

        let normalizedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "transcript"
            : prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseFilename = "\(normalizedPrefix)-\(timestamp)-\(backend.fileSlug)"
        let fileURL = uniqueTranscriptURL(forBaseFilename: baseFilename)

        let content = """
        timestamp: \(now.ISO8601Format())
        backend: \(backend.rawValue)

        \(text)
        """

        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func uniqueTranscriptURL(forBaseFilename baseFilename: String) -> URL {
        let primary = folderURL.appendingPathComponent("\(baseFilename).txt")
        if !fileManager.fileExists(atPath: primary.path) {
            return primary
        }

        var suffix = 1
        while true {
            let candidate = folderURL.appendingPathComponent("\(baseFilename)-\(suffix).txt")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }
}
