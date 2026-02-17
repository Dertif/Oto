import Foundation
import XCTest
@testable import Oto

final class TranscriptHistoryStoreTests: XCTestCase {
    func testLoadEntriesIncludesOnlyTranscriptArtifactsAndExcludesFailureContext() throws {
        let folder = makeTempFolder(prefix: "TranscriptHistoryFilter")
        defer { try? FileManager.default.removeItem(at: folder) }

        try writeFile(
            folder: folder,
            name: "transcript-2026-02-17_10-00-00-000-apple-speech.txt",
            content: "timestamp: 2026-02-17T10:00:00Z\nbackend: Apple Speech\n\nbase"
        )
        try writeFile(
            folder: folder,
            name: "raw-transcript-2026-02-17_10-01-00-000-whisper.txt",
            content: "timestamp: 2026-02-17T10:01:00Z\nbackend: WhisperKit\n\nraw"
        )
        try writeFile(
            folder: folder,
            name: "refined-transcript-2026-02-17_10-02-00-000-whisper.txt",
            content: "timestamp: 2026-02-17T10:02:00Z\nbackend: WhisperKit\n\nrefined"
        )
        try writeFile(
            folder: folder,
            name: "failure-context-2026-02-17_10-03-00-000-whisper.txt",
            content: "should be excluded"
        )
        try writeFile(
            folder: folder,
            name: "notes.txt",
            content: "should be excluded"
        )

        let store = TranscriptHistoryStore(folderURL: folder)
        let entries = try store.loadEntries()

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(Set(entries.map(\.kind)), Set([.transcript, .raw, .refined]))

        let refined = try XCTUnwrap(entries.first(where: { $0.kind == .refined }))
        XCTAssertTrue(refined.isEnhanced)

        let nonRefined = entries.filter { $0.kind != .refined }
        XCTAssertTrue(nonRefined.allSatisfy { !$0.isEnhanced })
    }

    func testLoadEntriesSortsMostRecentFirst() throws {
        let folder = makeTempFolder(prefix: "TranscriptHistorySort")
        defer { try? FileManager.default.removeItem(at: folder) }

        try writeFile(
            folder: folder,
            name: "transcript-2026-02-17_08-00-00-000-apple-speech.txt",
            content: "timestamp: 2026-02-17T08:00:00Z\nbackend: Apple Speech\n\nolder"
        )
        try writeFile(
            folder: folder,
            name: "transcript-2026-02-17_09-30-00-000-apple-speech.txt",
            content: "timestamp: 2026-02-17T09:30:00Z\nbackend: Apple Speech\n\nnewer"
        )

        let store = TranscriptHistoryStore(folderURL: folder)
        let entries = try store.loadEntries()

        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries[0].timestamp > entries[1].timestamp)
        XCTAssertTrue(entries[0].textBody.contains("newer"))
    }

    func testLoadEntriesUsesTimestampFallbackChain() throws {
        let folder = makeTempFolder(prefix: "TranscriptHistoryFallback")
        defer { try? FileManager.default.removeItem(at: folder) }

        let fromFilenameURL = try writeFile(
            folder: folder,
            name: "transcript-2026-02-17_11-22-33-444-whisper.txt",
            content: "plain body"
        )

        let modificationDate = Date(timeIntervalSince1970: 1_760_399_999)
        let fromModificationURL = try writeFile(
            folder: folder,
            name: "transcript-random-whisper.txt",
            content: "another body"
        )
        try FileManager.default.setAttributes(
            [.modificationDate: modificationDate],
            ofItemAtPath: fromModificationURL.path
        )

        let store = TranscriptHistoryStore(folderURL: folder)
        let entries = try store.loadEntries()

        let filenameEntry = try XCTUnwrap(entries.first(where: { $0.url.lastPathComponent == fromFilenameURL.lastPathComponent }))
        XCTAssertEqual(filenameEntry.backendLabel, "WhisperKit")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let expectedFilenameDate = try XCTUnwrap(formatter.date(from: "2026-02-17_11-22-33-444"))
        XCTAssertEqual(filenameEntry.timestamp.timeIntervalSince1970, expectedFilenameDate.timeIntervalSince1970, accuracy: 0.001)

        let modificationEntry = try XCTUnwrap(entries.first(where: { $0.url.lastPathComponent == fromModificationURL.lastPathComponent }))
        XCTAssertEqual(modificationEntry.timestamp.timeIntervalSince1970, modificationDate.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(modificationEntry.textBody, "another body")
    }

    func testLoadEntriesStripsMetadataHeaderFromDisplayedBody() throws {
        let folder = makeTempFolder(prefix: "TranscriptHistoryBody")
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = try writeFile(
            folder: folder,
            name: "raw-transcript-2026-02-17_11-00-00-000-apple-speech.txt",
            content: "timestamp: 2026-02-17T11:00:00Z\nbackend: Apple Speech\n\nfirst line\nsecond line\n"
        )

        let store = TranscriptHistoryStore(folderURL: folder)
        let entries = try store.loadEntries()
        let entry = try XCTUnwrap(entries.first(where: { $0.url.lastPathComponent == url.lastPathComponent }))

        XCTAssertEqual(entry.backendLabel, "Apple Speech")
        XCTAssertEqual(entry.textBody, "first line\nsecond line")
        XCTAssertEqual(entry.lineCount, 2)
    }

    @discardableResult
    private func writeFile(folder: URL, name: String, content: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeTempFolder(prefix: String) -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
