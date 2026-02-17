import XCTest
@testable import Oto

final class TranscriptStoreTests: XCTestCase {
    func testBackToBackSavesProduceDistinctFilenames() throws {
        let tempFolder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OtoTranscriptStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempFolder)
        }

        let fixedDate = Date(timeIntervalSince1970: 1_739_411_200)
        let store = TranscriptStore(
            folderURL: tempFolder,
            nowProvider: { fixedDate }
        )

        let first = try store.save(text: "Hello one", backend: .appleSpeech)
        let second = try store.save(text: "Hello two", backend: .appleSpeech)

        XCTAssertNotEqual(first.lastPathComponent, second.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertTrue(second.lastPathComponent.contains("-1.txt"))
    }

    func testRawAndRefinedPrefixesCanCoexist() throws {
        let tempFolder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OtoTranscriptStorePrefixTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempFolder)
        }

        let fixedDate = Date(timeIntervalSince1970: 1_739_411_200)
        let store = TranscriptStore(
            folderURL: tempFolder,
            nowProvider: { fixedDate }
        )

        let rawURL = try store.save(text: "raw text", backend: .appleSpeech, prefix: "raw-transcript")
        let refinedURL = try store.save(text: "refined text", backend: .appleSpeech, prefix: "refined-transcript")

        XCTAssertTrue(rawURL.lastPathComponent.contains("raw-transcript-"))
        XCTAssertTrue(refinedURL.lastPathComponent.contains("refined-transcript-"))
        XCTAssertNotEqual(rawURL.lastPathComponent, refinedURL.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rawURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: refinedURL.path))
    }
}
