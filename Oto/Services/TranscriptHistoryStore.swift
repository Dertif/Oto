import Foundation

protocol TranscriptHistoryProviding: AnyObject {
    func loadEntries() throws -> [TranscriptHistoryEntry]
}

final class TranscriptHistoryStore: TranscriptHistoryProviding {
    private let folderURL: URL
    private let fileManager: FileManager

    init(
        folderURL: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/Oto/Transcripts", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.folderURL = folderURL
        self.fileManager = fileManager
    }

    func loadEntries() throws -> [TranscriptHistoryEntry] {
        guard fileManager.fileExists(atPath: folderURL.path) else {
            return []
        }

        let urls = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        var entries: [TranscriptHistoryEntry] = []
        entries.reserveCapacity(urls.count)

        for url in urls {
            guard url.pathExtension.lowercased() == "txt" else {
                continue
            }

            let filename = url.deletingPathExtension().lastPathComponent
            guard let kind = kind(forFilename: filename) else {
                continue
            }

            let content = try String(contentsOf: url, encoding: .utf8)
            let metadata = parseMetadataAndBody(from: content)

            let timestamp = metadata.timestamp
                ?? timestampFromFilename(filename)
                ?? modificationDate(for: url)
                ?? .distantPast

            let backendLabel = metadata.backendLabel
                ?? backendFromFilename(filename)
                ?? "Unknown"

            let lineCount = metadata.body.isEmpty ? 0 : metadata.body.split(whereSeparator: \.isNewline).count

            entries.append(TranscriptHistoryEntry(
                id: url.path,
                url: url,
                kind: kind,
                isEnhanced: kind == .refined,
                timestamp: timestamp,
                backendLabel: backendLabel,
                textBody: metadata.body,
                lineCount: lineCount
            ))
        }

        return entries.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.url.lastPathComponent > rhs.url.lastPathComponent
            }
            return lhs.timestamp > rhs.timestamp
        }
    }

    private func kind(forFilename filename: String) -> TranscriptArtifactKind? {
        if filename.hasPrefix("refined-transcript-") {
            return .refined
        }
        if filename.hasPrefix("raw-transcript-") {
            return .raw
        }
        if filename.hasPrefix("failure-context-") {
            return .failureContext
        }
        if filename.hasPrefix("transcript-") {
            return .transcript
        }
        return nil
    }

    private func parseMetadataAndBody(from rawContent: String) -> (timestamp: Date?, backendLabel: String?, body: String) {
        let normalized = rawContent.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var metadata: [String: String] = [:]
        var bodyStartIndex: Int?

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                bodyStartIndex = index + 1
                break
            }

            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                break
            }

            let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            metadata[key] = value
        }

        let body: String
        if let bodyStartIndex, !metadata.isEmpty, bodyStartIndex <= lines.count {
            body = lines[bodyStartIndex...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            body = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let metadataTimestamp = metadata["timestamp"].flatMap(parseISO8601Date)
        let backendLabel = metadata["backend"]

        return (metadataTimestamp, backendLabel, body)
    }

    private func parseISO8601Date(_ value: String) -> Date? {
        let parser = ISO8601DateFormatter()
        if let date = parser.date(from: value) {
            return date
        }

        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: value)
    }

    private func timestampFromFilename(_ filename: String) -> Date? {
        guard let range = filename.range(of: #"\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}-\d{3}"#, options: .regularExpression) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        return formatter.date(from: String(filename[range]))
    }

    private func backendFromFilename(_ filename: String) -> String? {
        if filename.contains("-apple-speech") {
            return STTBackend.appleSpeech.rawValue
        }
        if filename.contains("-whisper") {
            return STTBackend.whisper.rawValue
        }
        return nil
    }

    private func modificationDate(for url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }
}
