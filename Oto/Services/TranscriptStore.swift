import Foundation

final class TranscriptStore {
    let folderURL: URL

    init(folderURL: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/Oto/Transcripts", isDirectory: true)) {
        self.folderURL = folderURL
    }

    func save(text: String, backend: STTBackend) throws -> URL {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        let filename = "transcript-\(timestamp)-\(backend.fileSlug).txt"
        let fileURL = folderURL.appendingPathComponent(filename)

        let content = """
        timestamp: \(Date().ISO8601Format())
        backend: \(backend.rawValue)

        \(text)
        """

        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
